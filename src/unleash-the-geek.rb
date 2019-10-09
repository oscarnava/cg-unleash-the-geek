# frozen_string_literal: true

# Rank    Position  Total   Points
# Bronze      981   1,127    13.51
# Bronze      994   1,158    13.90
# Bronze      592   1,167    26.85
# Bronze      611   1,209    27.30
# Bronze      591   1,212    27.85
# Bronze      455   1,212    30.90
# Bronze      142     931    29.26
# Bronze       73     932    31.22
# Bronze      102     929    30.45
# Bronze       45     927    32.00
# Silver      528     560    12.00

STDOUT.sync = true # DO NOT REMOVE
# Deliver more ore to hq (left side of the map) than your opponent. Use radars to find ore but beware of traps!

alias org_gets gets
def gets
  org_gets # .tap { |v| warn v }
end

INT_TO_ITEM = { -1 => :none, 2 => :radar, 3 => :trap, 4 => :ore }.freeze
class Integer
  def sqr
    self * self
  end

  def to_item
    INT_TO_ITEM[self]
  end
end

WIDTH, HEIGHT = gets.split(' ').collect(&:to_i) # 30 x 15

SECTOR_SIZE = 5
HORZ_SECTORS = WIDTH / SECTOR_SIZE
VERT_SECTORS = HEIGHT / SECTOR_SIZE

class Position
  attr_reader :row, :col
  def initialize(row, col)
    @row = row.clamp(0, HEIGHT - 1)
    @col = col.clamp(0, WIDTH - 1)
  end

  def distance_to(pos)
    Math.sqrt((row - pos.row).sqr + (col - pos.col).sqr)
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
    @done = false
  end

  def move_to(target)
    yield if block_given?
    @gs.move_to target, msg: self.class
  end

  def move_to_hq
    move_to @bot.hq
  end

  def dig_at(target)
    yield if block_given?
    @gs.dig_at target, msg: self.class
  end

  def request(item)
    yield if block_given?
    @gs.request item, msg: self.class
  end

  def wait
    @gs.wait msg: self.class
  end

  def finish_by
    @done = true
    yield
  end

  def finished?
    @done || @bot.disabled?
  end
end

class NoTask < Task
  def initialize(state, bot)
    super state, bot
  end

  def next_command
    warn
  end
end

class ScanSectorTask < Task
  def initialize(state, bot, num = rand(VERT_SECTORS * HORZ_SECTORS))
    super state, bot
    # # @top = (num / HORZ_SECTORS) * SECTOR_SIZE
    # # @left = (num % HORZ_SECTORS) * SECTOR_SIZE
    # @target = Position.new(@top + rand(SECTOR_SIZE), @left + rand(SECTOR_SIZE))
  end

  def next_command
    @target = @gs.nearest_ore(@bot)&.pos
    return finish_by { wait } if @target.nil?

    if @bot.can_dig? @target
      finish_by { dig_at @target }
    else
      move_to @target
    end
  end
end

class PlaceRadarTask < Task
  def initialize(state, bot)
    super state, bot
  end

  def next_command
    unless @bot.carrying?(:radar)
      return move_to_hq unless @bot.at_hq?
      return wait unless @gs.can_place_radar?

      return request :RADAR
    end

    target = @gs.available_radar_pos

    if @bot.can_dig? target
      finish_by { dig_at target }
    else
      move_to target
    end
  end
end

class MineOreTask < Task
  def initialize(state, bot)
    super state, bot
  end

  def next_command
    unless (target = @gs.nearest_ore(@bot)&.pos)
      return finish_by { wait }
    end

    if @bot.can_dig? target
      finish_by { dig_at target }
    else
      move_to target
    end
  end
end

class DeliverOreTask < Task
  def initialize(state, bot)
    super state, bot
  end

  def next_command
    # warn "bot: #{@bot}, target: #{@target}"
    move_to_hq
  end

  def finished?
    @bot.at_hq?
  end
end

class PlaceTrapTask < Task
  attr_reader :target

  def initialize(state, bot)
    super state, bot
    @target = (state.nearest_ore(bot, min_size: 2, max_size: 2) ||
               state.nearest_ore(bot, min_size: 2))&.pos
  end

  def next_command
    return request :TRAP unless @bot.carrying? :trap

    @target = (@gs.nearest_ore(@bot, min_size: 2, max_size: 2) ||
               @gs.nearest_ore(@bot, min_size: 2))&.pos

    return wait if @target.nil?

    if @bot.can_dig? @target
      finish_by { dig_at @target }
    else
      move_to @target
    end
  end
end

class Cell
  attr_reader :ore, :hole, :pos, :entities

  def initialize(pos)
    @pos = pos
    @ore = nil
    @hole = nil
  end

  def entity=(entity)
    @entities = @entities.nil? ? [entity] : @entities << entity
  end

  def set_state(ore, hole)
    @ore = ore.to_i if ore != '?'
    @hole = :opponent if @hole.nil? && hole == '1'
    @entities = nil
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

  def trap?
    @entities&.any?(&:trap?)
  end

  def contains_item_type?(type)
    @entities&.any? { |itm| itm.is_a? type }
  end

  def decrement_ore(clear: false)
    @ore -= (clear ? @ore : 1) if contains_ore?
  end

  def distance_to(pos)
    @pos.distance_to(pos)
  end

  def to_s
    ent = if @entities.nil?
            ' '
          elsif @entities.size > 1
            @entities.size
          else
            @entities.first.to_s
          end
    "#{@ore || '.'}#{ent}"
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

  def nearest_ore(pos, min_size: 1, max_size: 99)
    @ores
      .select { |cell| cell.ore.between?(min_size, max_size) && !cell.trap? }
      .min_by { |cell| pos.distance_to cell.pos }
  end

  def decrement_ore(pos, clear: false)
    cell = self[pos]
    cell.decrement_ore clear: clear
    @ores.delete(cell) unless cell.contains_ore?
  end

  def ore_count
    @ores.map(&:ore).sum
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
    @cells
      .map { |row| row.join('') }
      .join("\n") # + "\n" + @ores.map(&:pos).join(',')
  end
end

class Entity
  attr_reader :id, :pos

  def initialize(id, col, row)
    @id = id
    @pos = Position.new(row, col)
  end

  def trap?
    false
  end
end

class Robot < Entity
  attr_reader :pos, :item
  attr_writer :task

  def initialize(id, col, row, item_id, owner)
    super id, col, row
    @item = item_id.to_item
    @owner = owner
    @last_pos = @pos
    @last_cmd = nil
  end

  def update(col, row, item_id)
    @last_pos = @pos
    @pos = Position.new(row, col)
    @item = item_id.to_item
    self
  end

  def distance_to(pos)
    @pos.distance_to pos
  end

  def nearest(pos1, pos2)
    distance_to(pos) < distance_to(pos2) ? pos1 : pos2
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

  def disabled?
    @pos.row.negative?
  end

  def carrying?(item = nil)
    item.nil? ? @item != :none : @item == item
  end

  def can_dig?(pos)
    @pos == pos ||
      @pos.col == pos.col && (@pos.row - pos.row).abs <= 1 ||
      @pos.row == pos.row && (@pos.col - pos.col).abs <= 1
  end

  def at_hq?
    @pos.col.zero?
  end

  def hq
    Position.new(pos.row, 0)
  end

  def finished_task?
    @task.nil? || @task.finished?
  end

  def next_command
    @last_cmd = @task&.next_command
  end

  def inspect
    "Robot \##{@id} @ [#{@pos}]" + mine? { enabled? ? " (#{@item})" : ' (X)' }.to_s
  end

  def to_s
    'R'
  end
end

class Radar < Entity
  def to_s
    'Y'
  end
end

class Trap < Entity
  def to_s
    '='
  end

  def trap?
    true
  end
end

RADAR_LOCATIONS = [
  Position.new(10, 5),
  Position.new(2, 5),
  Position.new(6, 10),
  Position.new(10, 15),
  Position.new(14, 10),
  Position.new(2, 15),
  Position.new(6, 20),
  Position.new(14, 20),
  Position.new(10, 25),
  Position.new(2, 25)
].freeze

class GameState
  class Command
    def initialize(action = :WAIT, pos: nil, item: nil, msg: nil)
      @act = action
      @pos = pos
      @itm = item
      @msg = msg
    end

    def action
      act
    end

    def to_s
      @msg = ''
      case @act
      when :MOVE, :DIG
        "#{@act} #{@pos} #{@msg}"
      when :REQUEST
        "#{@act} #{@itm} #{@msg}"
      else
        "#{@act} #{@msg}"
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

  def wait(msg: nil)
    Command.new(:WAIT, msg: msg)
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
        @items[id] = Radar.new(id, col, row)
      when 3
        @items[id] = Trap.new(id, col, row)
      end.tap { |entity| @board[entity.pos].entity = entity }
    end

    @my_bots = @robots.map(&:last).select(&:mine?)
  end

  def radar_available?
    @radar_cooldown.zero?
  end

  def available_radar_pos
    RADAR_LOCATIONS.find { |pos| !@board[pos].contains_item_type? Radar }
    # .tap { |loc| warn "Radar location: #{loc}" }
  end

  def can_place_radar?
    radar_available? && available_radar_pos
  end

  def trap_available?
    @trap_cooldown.zero?
  end

  def nearest_ore(bot, min_size: 1, max_size: 99)
    @board.nearest_ore(bot.pos, min_size: min_size, max_size: max_size)
  end

  def assign_tasks
    radar_avail = can_place_radar?
    trap_avail = trap_available?
    @my_bots.each do |bot|
      next unless bot.finished_task?

      bot.task = if bot.disabled?
                   NoTask.new self, bot
                 elsif bot.carrying? :ore
                   DeliverOreTask.new(self, bot)
                 elsif radar_avail && @board.ore_count < 10
                   PlaceRadarTask.new(self, bot).tap { radar_avail = false }
                 elsif bot.at_hq? && trap_avail && nearest_ore(bot, min_size: 2)
                   PlaceTrapTask.new(self, bot).tap { |tsk| @board.decrement_ore(tsk.target, clear: true); trap_avail = false }
                 elsif (ore_cell = nearest_ore(bot))
                   @board.decrement_ore(ore_cell.pos)
                   MineOreTask.new(self, bot)
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
