local Utils = require("scripts.utils")
local Core = {}

-- Applies the resource multiplier to a specific entity
-- Includes calculation logic and state updates
function Core.apply_multiplier(entity, multiplier)
    if not entity or not entity.valid then return false end
    
    local max_amount = 4294967295
    local new_amount = 0

    if entity.prototype.infinite_resource then
        -- Infinite resources: Ensure min base
        local min_base = settings.global["rich-resources-infinite-min-base"].value
        local base = entity.amount
        if base < min_base then base = min_base end
        new_amount = math.floor(base * multiplier)
    else
        -- Finite resources
        local base = entity.amount
        if base < 1 then base = 1 end
        new_amount = math.floor(base * multiplier)
    end

    if new_amount < 1 then new_amount = 1 end
    entity.amount = math.min(new_amount, max_amount)
    
    -- Update global processed list
    local entity_id = Utils.get_entity_identifier(entity)
    if entity_id then
        if global.richResources and global.richResources.processed_entities then
            global.richResources.processed_entities[entity_id] = true
        end
    end
    
    -- Update entity tags safely
    pcall(function() 
        local t = entity.tags or {}
        t.rich_resources_applied = true
        t.rich_resources_gen = (global.richResources and global.richResources.generation) or 1
        entity.tags = t
    end)

    return true
end

return Core
