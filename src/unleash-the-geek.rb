# frozen_string_literal: true

# Rank    Position  Total   Points
# Bronze      981   1,127    13.51

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

  def ==(other)
    other.is_a?(Position) && row == other.row && col == other.col
  end

  def to_s
    "#{@col} #{@row}"
  end
end

class Task
  def initialize(state, bot)
    @gs = state
    @bot = bot
  end

  def move_to(target)
    yield if block_given?
    @gs.move_to target, msg: self.class
  end

  def dig_at(target)
    yield if block_given?
    @gs.dig_at target, msg: self.class
  end

  def request(item)
    yield if block_given?
    @gs.request item, msg: self.class
  end
end

class ScanSectorTask < Task
  def initialize(state, bot, num = rand(VERT_SECTORS * HORZ_SECTORS))
    super state, bot
    @top = (num / HORZ_SECTORS) * SECTOR_SIZE
    @left = (num % HORZ_SECTORS) * SECTOR_SIZE
    @target = Position.new(@top + rand(SECTOR_SIZE), @left + rand(SECTOR_SIZE))
  end

  def next_command
    if @bot.at_hq? && @gs.radar_available? && !@bot.carrying?
      @target = Position.new(@top + SECTOR_SIZE / 2, @left + SECTOR_SIZE / 2)
      request :RADAR
    elsif @bot.can_dig? @target
      dig_at @target do
        @target = nil
      end
    else
      move_to @target
    end
  end

  def finished?
    @target.nil?
  end
end

class MineOreTask < Task
  def initialize(state, bot, cell)
    super state, bot
    @target = cell.pos
  end

  def next_command
    if @bot.can_dig? @target
      dig_at @target do
        @target = nil
      end
    else
      move_to @target
    end
  end

  def finished?
    @target.nil?
  end
end

class DeliverOreTask < Task
  def initialize(state, bot)
    super state, bot
    @target = Position.new(bot.pos.row, 0)
  end

  def next_command
    warn "bot: #{@bot}, target: #{@target}"
    if @bot.pos.col <= 4
      move_to @target do
        @target = nil
      end
    else
      move_to @target
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
    @ore = nil
    @hole = nil
  end

  def set_state(ore, hole)
    @ore = ore.to_i if ore != '?'
    @hole = :opponent if @hole.nil? && hole == '1'
  end

  def claim_hole
    @hole = :player
  end

  def my_hole?
    @hole == :player
  end

  def contains_ore?
    @ore&.positive?
  end

  def decrement_ore
    @ore -= 1 if contains_ore?
  end

  def distance_to(pos)
    @pos.distance_to(pos)
  end

  def to_s
    "[#{@ore}]"
  end
end

class Board
  def initialize
    @cells = Array.new(HEIGHT) { |row| Array.new(WIDTH) { |col| Cell.new(Position.new(row, col)) } }
    @ores = []
  end

  def [](pos)
    @cells[pos.row][pos.col]
  end

  def ore(pos)
    @cells[pos.row][pos.col].ore
  end

  def hole(pos)
    @cells[pos.row][pos.col].hole
  end

  def nearest_ore(pos)
    @ores.min_by { |cell| pos.distance_to cell.pos }
  end

  def read_state
    @ores = []
    HEIGHT.times do |row|
      # ore: amount of ore or "?" if unknown
      # hole: 1 if cell has a hole
      cells = @cells[row].each
      gets.split(' ').each_slice(2) do |ore, hole|
        cell = cells.next
        cell.set_state(ore, hole)
        @ores << cell if cell.contains_ore?
      end
    end
  end

  def to_s
    @cells.map do |row|
      row.map do |cell|
        cell&.ore || '?'
      end.join('.')
    end.join("\n") + "\n" + @ores.map(&:pos).join(',')
  end
end

class Entity
  attr_reader :id

  def initialize(id)
    @id = id
  end
end

class Robot < Entity
  attr_reader :pos, :item
  attr_writer :task

  def initialize(id, col, row, item_id, owner)
    super id
    @pos = Position.new(row, col)
    @item = INT_TO_ITEM[item_id]
    @owner = owner
    @last_pos = @pos
    @last_cmd = nil
  end

  def update(col, row, item_id)
    @last_pos = @pos
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

  def carrying?
    @item != :none
  end

  def can_dig?(pos)
    @pos == pos ||
      @pos.col == pos.col && (@pos.row - pos.row).abs <= 1 ||
      @pos.row == pos.row && (@pos.col - pos.col).abs <= 1
  end

  def at_hq?
    @pos.col.zero?
  end

  def finished_task?
    @task.nil? || @task.finished?
  end

  def next_command
    @last_cmd = @task&.next_command
  end

  def to_s
    "Robot \##{@id} @ [#{@pos}]" + mine? { enabled? ? " (#{@item})" : ' (X)' }.to_s
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
        "#{@act} #{@pos} #{@msg}"
      when :REQUEST
        "#{@act} #{@itm} #{@msg}"
      else
        @act.to_s
      end
    end
  end

  def initialize
    @board = Board.new
    @score = 0
    @enemy_score = 0
    @entity_count = 0
    @radar_cooldown = 0
    @trap_cooldown = 0
    @robots = {}
    @my_bots = []
    @items = {}
  end

  def move_to(target, msg: nil)
    Command.new(:MOVE, pos: target, msg: msg)
  end

  def dig_at(target, msg: nil)
    @board[target].claim_hole
    Command.new(:DIG, pos: target, msg: msg)
  end

  def request(item, msg: nil)
    case item
    when :RADAR
      @radar_cooldown = 5
    when :TRAP
      @trap_cooldown = 5
    end
    Command.new(:REQUEST, item: item, msg: msg)
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

  def nearest_ore(bot)
    @board.nearest_ore bot.pos
  end

  def assign_tasks
    @my_bots.each do |bot|
      next unless bot.finished_task?

      bot.task = if bot.carrying?
                   DeliverOreTask.new(self, bot)
                 elsif !(bot.at_hq? && radar_available?) && (ore_cell = nearest_ore(bot))
                   ore_cell.decrement_ore
                   MineOreTask.new(self, bot, ore_cell)
                 else
                   ScanSectorTask.new(self, bot)
                 end
    end
  end

  def clear_tasks
    @my_bots.each { |bot| bot.task = nil if bot.finished_task? }
  end

  # WAIT|MOVE x y|DIG x y|REQUEST item
  def moves
    # warn "Explorer: #{explorer.last}"
    # warn @robots.map(&:last)
    # warn @items.map(&:last)

    clear_tasks
    assign_tasks

    @my_bots.map(&:next_command)
  end

  def to_s
    @board.to_s
  end
end

# game loop
gs = GameState.new

loop do
  gs.read_state
  # warn gs
  puts gs.moves
end
