# frozen_string_literal: true

STDOUT.sync = true # DO NOT REMOVE
# Deliver more ore to hq (left side of the map) than your opponent. Use radars to find ore but beware of traps!

# height: size of the map
width, height = gets.split(' ').collect(&:to_i)

# game loop
loop do
  # my_score: Amount of ore delivered
  my_score, opponent_score = gets.split(' ').collect(&:to_i)
  height.times do
    inputs = gets.split(' ')
    (0..(width - 1)).each do |j|
      # ore: amount of ore or "?" if unknown
      # hole: 1 if cell has a hole
      ore = inputs[2 * j]
      hole = inputs[2 * j + 1].to_i
    end
  end
  # entity_count: number of entities visible to you
  # radar_cooldown: turns left until a new radar can be requested
  # trap_cooldown: turns left until a new trap can be requested
  entity_count, radar_cooldown, trap_cooldown = gets.split(' ').collect(&:to_i)
  entity_count.times do
    # id: unique id of the entity
    # type: 0 for your robot, 1 for other robot, 2 for radar, 3 for trap
    # y: position of the entity
    # item: if this entity is a robot, the item it is carrying (-1 for NONE, 2 for RADAR, 3 for TRAP, 4 for ORE)
    id, type, x, y, item = gets.split(' ').collect(&:to_i)
  end
  5.times do
    # Write an action using puts
    # To debug: STDERR.puts "Debug messages..."

    puts 'WAIT' # WAIT|MOVE x y|DIG x y|REQUEST item
  end
end
