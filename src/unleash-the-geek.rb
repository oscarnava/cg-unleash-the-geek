# frozen_string_literal: true

STDOUT.sync = true # DO NOT REMOVE
# Deliver more ore to hq (left side of the map) than your opponent. Use radars to find ore but beware of traps!

alias org_gets gets
def gets
  org_gets.tap { |v| warn v }
end

# height: size of the map
WIDTH, HEIGHT = gets.split(' ').collect(&:to_i)
INT_TO_ITEM = { -1 => :none, 2 => :radar, 3 => :trap, 4 => :ore }.freeze

class Position
  attr_reader :row, :col
  def initialize(row, col)
    @row = row
    @col = col
  end

  def move(dir)
    case dir
    when :DOWN
      return Position(row + 1, col) if row < HEIGHT
    when :UP
      return Position(row - 1, col) if row.positive?
    when :RIGHT
      return Position(row, col + 1) if col < WIDTH
    when :LEFT
      return Position(row, col - 1) if col.positive?
    end
  end
end

class Board
  def initialize
    @cells = Array.new(HEIGHT) { Array.new(2 * WIDTH) }
  end

  def ore(pos)
    (v = @cells[pos.row][2 * pos.col]) == '?' ? nil : v.to_i
  end

  def hole?(pos)
    @cells[pos.row][2 * pos.col + 1] == '1'
  end

  def read_state
    HEIGHT.times do |row|
      # ore: amount of ore or "?" if unknown
      # hole: 1 if cell has a hole
      @cells[row] = gets.split(' ')
    end
  end
end

class Entity
  attr_reader :id

  def initialize(id)
    @id = id
  end

  def self.build(id, type, col, row, item)
    case type
    when 0, 1
      Robot.new(id, Position.new(row, col), item: INT_TO_ITEM[item], its_mine: type.zero?)
    when 2
      Radar.new(id)
    when 3
      Trap.new(id)
    end
  end
end

class Robot < Entity
  attr_accessor :item

  def initialize(id, pos, item: :none, its_mine: true)
    super id
    @pos = pos
    @item = item
    @its_mine = its_mine
  end
end

class Radar < Entity
  def initialize(id)
    super id
  end
end

class Trap < Entity
  def initialize(id)
    super id
  end
end

class GameState
  def initialize
    @score = 0
    @enemy_score = 0
    @board = Board.new
    @entities = {}
  end

  def read_state
    # my_score: Amount of ore delivered
    @score, @enemy_score = gets.split(' ').collect(&:to_i)
    @board.read_state

    # entity_count: number of entities visible to you
    # radar_cooldown: turns left until a new radar can be requested
    # trap_cooldown: turns left until a new trap can be requested
    @entity_count, @radar_cooldown, @trap_cooldown = gets.split(' ').collect(&:to_i)
    @entity_count.times do
      # id: unique id of the entity
      # type: 0 for your robot, 1 for other robot, 2 for radar, 3 for trap
      # y: position of the entity
      # item: if this entity is a robot, the item it is carrying (-1 for NONE, 2 for RADAR, 3 for TRAP, 4 for ORE)
      Entity.build(* gets.split(' ').collect(&:to_i)).tap do |entity|
        @entities[entity.id] = entity
      end
    end
  end
end

# game loop
gs = GameState.new

loop do
  gs.read_state
  5.times do
    # Write an action using puts
    # To debug: STDERR.puts "Debug messages..."
    puts 'WAIT' # WAIT|MOVE x y|DIG x y|REQUEST item
  end
end
