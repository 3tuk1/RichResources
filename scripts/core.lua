local Core = {}

function Core.apply_multiplier(entity, base_multiplier, rng)
    if not entity or not entity.valid then return false end
    
    local multiplier = base_multiplier

    local randomness = settings.global["rich-resources-randomness-factor"].value
    if randomness > 0 then
        -- Desync protection: Always use provided RNG
        local r_val = 0.5
        if rng then
             r_val = rng()
        else
             -- Fallback for safety, though caller should always provide rng in MP
             -- Using game.create_random_generator without args uses a predetermined seed if not careful, 
             -- but better creates a new one. 
             -- However, without a seed it's not deterministic across clients if called in a loop.
             -- As a fallback, we can use a deterministic property of the entity.
             local seed = (entity.position.x * 1000) + (entity.position.y * 1000)
             r_val = game.create_random_generator(seed)()
        end

        local variance = (r_val * 2.0) - 1.0
        local offset = variance * randomness
        multiplier = multiplier * (1.0 + offset)
    end

    local dist_enabled = settings.global["richresources-enable-distance-bonus"] and settings.global["richresources-enable-distance-bonus"].value
    if dist_enabled then
        local pos = entity.position
        if pos then
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
    local base = entity.amount

    if entity.prototype.infinite_resource then
        local min_base = settings.global["rich-resources-infinite-min-base"].value
        if base < min_base then base = min_base end
        new_amount = math.floor(base * multiplier)
    else
        local min_base = settings.global["rich-resources-finite-min-base"] and settings.global["rich-resources-finite-min-base"].value or 1
        if base < min_base then base = min_base end
        new_amount = math.floor(base * multiplier)
    end

    if new_amount < 1 then new_amount = 1 end
    entity.amount = math.min(new_amount, max_amount)

    return true
end

return Core
