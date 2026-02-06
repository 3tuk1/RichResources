local Utils = {}

function Utils.get_entity_identifier(entity)
  if entity.unit_number then return entity.unit_number end
  if entity.valid and entity.position then
    return string.format("%d_%.2f_%.2f", entity.surface.index, entity.position.x, entity.position.y)
  end
  return nil
end

return Utils
