# frozen_string_literal: true

STDOUT.sync = true # DO NOT REMOVE
# Deliver more ore to hq (left side of the map) than your opponent. Use radars to find ore but beware of traps!

alias org_gets gets
def gets
  org_gets # .tap { |v| warn v }
end

def sqr(num)
  num * num
end

WIDTH, HEIGHT = gets.split(' ').collect(&:to_i) # 30 x 15
INT_TO_ITEM = { -1 => :none, 2 => :radar, 3 => :trap, 4 => :ore }.freeze
SECTOR_SIZE = 5
HORZ_SECTORS = WIDTH / SECTOR_SIZE
VERT_SECTORS = HEIGHT / SECTOR_SIZE

class Position
  attr_reader :row, :col
  def initialize(row, col)
    @row = row
    @col = col
  end

  def distance_to(pos)
    Math.sqrt(sqr(row - pos.row) + sqr(col - pos.col))
  end

  def self.random
    Position.new(rand(HEIGHT), rand(WIDTH))
  end

  def ==(pos)
    pos.is_a?(Position) && row == pos.row && col == pos.col
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

  def to_s
    "#{@col} #{@row}"
  end
end

class Command
  def initialize(action = :WAIT, pos: nil, item: nil, msg: nil)
    @act = action
    @pos = pos
    @itm = item
    @msg = msg
  end

  def self.random
    Command.new(:DIG, pos: Position.random)
  end

  def to_s
    case @act
    when :MOVE, :DIG
      "#{@act} #{@pos}"
    when :REQUEST
      "#{@act} #{@itm}"
    else
      @act.to_s
    end
  end
end

class ScanSectorTask
  def initialize(num = rand(VERT_SECTORS * HORZ_SECTORS))
    row = num % VERT_SECTORS
    col = num % HORZ_SECTORS
    # @horz = (left * SECTOR_SIZE)...((left + 1) * SECTOR_SIZE)
    # @vert = (top * SECTOR_SIZE)...((top + 1) * SECTOR_SIZE)
    @target = Position.new(row * SECTOR_SIZE + rand(SECTOR_SIZE), col * SECTOR_SIZE + rand(SECTOR_SIZE))
  end

  def next_command(robot)
    if robot.can_dig? @target
      Command.new(:DIG, pos: @target).tap { @target = nil }
    else
      Command.new(:MOVE, pos: @target)
    end
  end

  def finished?
    @target.nil?
  end
end

class Cell
  attr_reader :ore, :hole
  attr_reader :pos

  def initialize(pos)
    @pos = pos
  end

  def set_values(ore, hole)
    @ore = ore == '?' ? nil : ore.to_i
    @hole = hole == '1'
  end

  def distance_to(pos)
    @pos.distance_to(pos)
  end
end

class Board
  def initialize
    @cells = Array.new(HEIGHT) { |row| Array.new(2 * WIDTH) { |col| Cell.new(Position.new(row, col)) } }
    @ores = []
  end

  def ore(pos)
    @cells[pos.row][pos.col].ore
  end

  def hole?(pos)
    @cells[pos.row][pos.col].hole
  end

  def nearest_ore(pos)
    @ores.min_by { |cell| pos.distance_to cell.pos }
  end

  def read_state
    HEIGHT.times do |row|
      # ore: amount of ore or "?" if unknown
      # hole: 1 if cell has a hole
      cells = @cells[row].each
      gets.split(' ').each_slice(2) do |ore, hole|
        cell = cells.next
        cell.set_values(ore, hole)
        @ores << cell if cell.ore
      end
    end
  end
end

class Entity
  attr_reader :id

  def initialize(id)
    @id = id
  end
end

class Robot < Entity
  attr_reader :item
  attr_accessor :task

  def initialize(id, col, row, item_id, owner)
    super id
    @pos = Position.new(row, col)
    @item = INT_TO_ITEM[item_id]
    @owner = owner
  end

  def update(col, row, item_id)
    @pos = Position.new(row, col)
    @item = INT_TO_ITEM[item_id]
    self
  end

  def mine?
    if block_given?
      yield if @owner.zero?
    else
      @owner.zero?
    end
  end

  def enabled?
    !@pos.row.negative?
  end

  def can_dig?(pos)
    @pos == pos ||
      @pos.col == pos.col && (@pos.row - pos.row).abs <= 1 ||
      @pos.row == pos.row && (@pos.col - pos.col).abs <= 1
  end

  def to_s
    "Robot \##{@id} @ [#{@pos}]" + mine? { enabled? ? " (#{@item || 'None'})" : ' (X)' }.to_s
  end
end

class Radar < Entity
  def initialize(id)
    super id
  end

  def to_s
    "Radar \##{@id} @ [#{@pos}]"
  end
end

class Trap < Entity
  def initialize(id)
    super id
  end

  def to_s
    "Trap \##{@id} @ [#{@pos}]"
  end
end

class GameState
  def initialize
    @score = 0
    @enemy_score = 0
    @entity_count = 0
    @radar_cooldown = 0
    @trap_cooldown = 0
    @board = Board.new
    @robots = {}
    @my_bots = []
    @items = {}
  end

  def read_state
    # my_score: Amount of ore delivered
    @score, @enemy_score = gets.split(' ').collect(&:to_i)
    @board.read_state
    @items = {}

    # entity_count: number of entities visible to you
    # radar_cooldown: turns left until a new radar can be requested
    # trap_cooldown: turns left until a new trap can be requested
    @entity_count, @radar_cooldown, @trap_cooldown = gets.split(' ').collect(&:to_i)
    @entity_count.times do
      # id: unique id of the entity
      # type: 0 for your robot, 1 for other robot, 2 for radar, 3 for trap
      # y: position of the entity
      # item: if this entity is a robot, the item it is carrying (-1 for NONE, 2 for RADAR, 3 for TRAP, 4 for ORE)

      id, type, col, row, item_id = gets.split(' ').collect(&:to_i)

      case type
      when 0, 1
        @robots[id] = @robots[id]&.update(col, row, item_id) || Robot.new(id, col, row, item_id, type)
      when 2
        @items[id] = Radar.new(id)
      when 3
        @items[id] = Trap.new(id)
      end
    end

    @my_bots = @robots.map(&:last).select(&:mine?)
  end

  def radar_available?
    @radar_cooldown.zero?
  end

  def trap_available?
    @trap_cooldown.zero?
  end

  def explorer
    @robots.first { |bot| bot.enabled? && bot.mine? }
  end

  def assign_tasks
    @my_bots.each { |bot| bot.task = ScanSectorTask.new if bot.task.nil? }
  end

  def clear_tasks
    @my_bots.each { |bot| bot.task = nil if bot.task&.finished? }
  end

  # WAIT|MOVE x y|DIG x y|REQUEST item
  def moves
    warn "Explorer: #{explorer.last}"
    warn @robots.map(&:last)
    warn @items.map(&:last)

    clear_tasks
    assign_tasks

    @my_bots.map { |bot| bot.task.next_command(bot) }

    # [Command.random, Command.random, Command.random, Command.random, Command.random]
  end
end

# game loop
gs = GameState.new

loop do
  gs.read_state
  puts gs.moves
end
