--[[
This module is a type introspection library. Type information can be registered into a table, and functions are provided to copy and manipulate Lua values as though they are instances of a registered type.
]]

local module = {}

local common = require("common")

module.TRAVERSAL_TYPE = {
    --[[
    Object treated as a singular value or pointer. Any unrecognized traversal type defaults to this behavior.
    Create snapshot: Returns plain reference to object.
    Apply snapshot: Destination object is fully replaced by the snapshot object.
    Lua types: any
    ]]
    NONE = 1,
    --[[
    Collection of elements matching a predefined list of fields. Traversal assumes all elements are compatible with their field type, and skips elements that have no matching field.
    Create snapshot: Creates a new table where each element is a field name key mapped to a recursively copied value.
    Apply snapshot: Destination object pointer is not changed. The snapshot is applied recursively for each class field.
    Lua types: table, userdata, nil
    ]]
    CLASS = 2,
    --[[
    Fixed-length array of elements with the same type. A structural array behaves like a class object where each index in the array is a class field.
    Create snapshot: Creates new table where each element is an array index key mapped to a recursively copied value.
    Apply snapshot: Destination object pointer is not changed. The snapshot is applied recursively for each array index. Both arrays are expected to have the same length.
    Lua types: table, userdata, nil
    ]]
    STRUCTURAL_ARRAY = 3,
    --[[
    Array of elements with the same type.
    Create snapshot: Creates new table where each element is an array index key mapped to a recursively copied value.
    Apply snapshot: Destination object pointer is not changed. For each index in the snapshot array, the destination value is fully replaced by the snapshot value. If the snapshot array is longer, then the extra values are appended to the destination array. If the destination array is longer, then the extra values are cleared.
    Lua types: table, userdata, nil
    ]]
    ARRAY = 4
}

function module.register_types(types, raw_types)
    -- Create an unfinished type definition for each raw type. These need to be defined ahead of time for name lookups in subsequent loops.
    for type_name, raw_type in pairs(raw_types) do
        local this_type = {
            name = type_name
        }
        types[type_name] = this_type
        for k, v in pairs(raw_type) do
            -- Create shallow copies of all type parameters, including unrecognized ones.
            this_type[k] = v
        end
    end
    -- Register most of the type definition.
    for type_name, _ in pairs(raw_types) do
        local this_type = types[type_name]
        if this_type.traversal_type == module.TRAVERSAL_TYPE.CLASS then
            this_type.parent = types[this_type.parent]
            this_type.hierarchy = {}
            local ancestor_class = this_type
            while ancestor_class do
                table.insert(this_type.hierarchy, 1, ancestor_class)
                ancestor_class = ancestor_class.parent
            end
            local raw_fields = this_type.fields
            this_type.fields = {}
            this_type.fields_by_name = {}
            if raw_fields then
                for i, raw_field in ipairs(raw_fields) do
                    local field = {
                        name = raw_field.name,
                        is_method = raw_field.is_method,
                        getter = raw_field.getter,
                        setter = raw_field.setter,
                        array_size = raw_field.array_size
                    }
                    this_type.fields[i] = field
                    this_type.fields_by_name[field.name] = field
                    if type(raw_field.type) == "string" then
                        field.type = types[raw_field.type]
                        if not field.type then
                            field.type = {
                                name = raw_field.type
                            }
                        end
                    else
                        field.type = {}
                        for k, v in pairs(raw_field.type) do
                            -- Create shallow copies of all field type parameters, including unrecognized ones.
                            field.type[k] = v
                        end
                        if type(field.type.element_type) == "string" then
                            local element_type_name = field.type.element_type
                            field.type.element_type = types[element_type_name]
                            if not field.type.element_type then
                                field.type.element_type = {
                                    name = element_type_name
                                }
                            end
                        end
                    end
                end
            end
        end
    end
    -- Calculate class hierarchies.
    for type_name, _ in pairs(raw_types) do
        local this_type = types[type_name]
        if this_type.traversal_type == module.TRAVERSAL_TYPE.CLASS then
            this_type.hierarchy = {}
            local ancestor_class = this_type
            while ancestor_class do
                table.insert(this_type.hierarchy, 1, ancestor_class)
                ancestor_class = ancestor_class.parent
            end
        end
    end
    return types
end

-- Recursively create a snapshot of this object.
function module.create_snapshot(obj, obj_type)
    if obj == nil then
        return nil
    elseif obj_type.traversal_type == module.TRAVERSAL_TYPE.CLASS then
        local copy = {}
        for _, class in ipairs(obj_type.hierarchy) do
            if class.fields then
                for _, field in ipairs(class.fields) do
                    local field_value
                    if field.is_method then
                        if field.getter then
                            field_value = obj[field.getter](obj)
                        end
                    else
                        field_value = obj[field.name]
                    end
                    copy[field.name] = module.create_snapshot(field_value, field.type)
                end
            end
        end
        return copy
    elseif obj_type.traversal_type == module.TRAVERSAL_TYPE.STRUCTURAL_ARRAY then
        local copy = {}
        for i = 1, obj_type.array_size do
            copy[i] = module.create_snapshot(obj[i], obj_type.element_type)
        end
        return copy
    elseif obj_type.traversal_type == module.TRAVERSAL_TYPE.ARRAY then
        local copy = {}
        for i, v in ipairs(obj) do
            copy[i] = module.create_snapshot(v, obj_type.element_type)
        end
        return copy
    else
        return obj
    end
end

local function get_field_value(obj, field)
    if field.is_method then
        if field.getter then
            return obj[field.getter](obj)
        end
    else
       return obj[field.name]
    end
end

local function apply_snapshot_field(dest_obj, src_obj, field)
    if field.type.traversal_type == module.TRAVERSAL_TYPE.CLASS then
        local sub_dest_obj = get_field_value(dest_obj, field)
        for _, class in ipairs(field.type.hierarchy) do
            if class.fields then
                for _, sub_field in pairs(class.fields) do
                    apply_snapshot_field(sub_dest_obj, src_obj[field.name], sub_field)
                end
            end
        end
    elseif field.type.traversal_type == module.TRAVERSAL_TYPE.STRUCTURAL_ARRAY then
        local sub_dest_obj = get_field_value(dest_obj, field)
        for i = 1, field.type.array_size do
            apply_snapshot_field(sub_dest_obj, src_obj[field.name], { type = field.type.element_type, name = i })
        end
    elseif field.type.traversal_type == module.TRAVERSAL_TYPE.ARRAY then
        local sub_dest_obj = get_field_value(dest_obj, field)
        local sub_src_obj = src_obj[field.name]
        local max_size = field.type.array_size or math.max(#sub_dest_obj, #sub_src_obj)
        for i = 1, max_size do
            if i > #sub_src_obj then
                sub_dest_obj[i] = nil
            else
                sub_dest_obj[i] = common.deep_copy(sub_src_obj[i])
            end
        end
    else
        if field.is_method then
            if field.setter then
                dest_obj[field.setter](dest_obj, src_obj[field.name])
            end
        else
            dest_obj[field.name] = common.deep_copy(src_obj[field.name])
        end
    end
end

-- Recursively overwrite a table or userdata object with a snapshot object.
function module.apply_snapshot(dest_obj, src_obj, obj_type)
    apply_snapshot_field({ dest_obj }, { src_obj }, { type = obj_type, name = 1 })
end

return module
