local Utils = require("scripts.utils")
local Core = {}

-- Applies the resource multiplier to a specific entity
-- Includes calculation logic and state updates
-- rng: Optional LuaRandomGenerator for deterministic results
function Core.apply_multiplier(entity, base_multiplier, rng)
    if not entity or not entity.valid then return false end
    
    local multiplier = base_multiplier

    -- Apply Random Variance
    local randomness = settings.global["rich-resources-randomness-factor"].value
    if randomness > 0 then
        local r_val = 0
        if rng then
            r_val = rng() -- 0.0 to 1.0
        else
            r_val = math.random()
        end
        local variance = (r_val * 2.0) - 1.0 -- -1.0 to 1.0
        local offset = variance * randomness
        multiplier = multiplier * (1.0 + offset)
    end

    -- Apply Distance Bonus
    local dist_enabled = settings.global["richresources-enable-distance-bonus"] and settings.global["richresources-enable-distance-bonus"].value
    if dist_enabled then
        local pos = entity.position
        if pos then
            -- Calculate distance from (0,0)
            local dist = math.sqrt(pos.x * pos.x + pos.y * pos.y)
            local interval = settings.global["richresources-distance-interval"].value
            local rate = settings.global["richresources-distance-rate"].value
            
            if interval > 0 then
                local bonus_factor = math.floor(dist / interval) * rate
                multiplier = multiplier * (1.0 + bonus_factor)
            end
        end
    end

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
        if global and global.richResources and global.richResources.processed_entities then
            global.richResources.processed_entities[entity_id] = true
        end
    end
    
    -- Update entity tags safely
    pcall(function() 
        local t = entity.tags or {}
        t.rich_resources_applied = true
        local gen = 1
        if global and global.richResources and global.richResources.generation then
            gen = global.richResources.generation
        end
        t.rich_resources_gen = gen
        entity.tags = t
    end)

    return true
end

return Core
