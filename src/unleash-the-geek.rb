# frozen_string_literal: false

DEBUG = false

# Rank    Position  Total   Global  Points
# Bronze      981   1,127            13.51
# Bronze      994   1,158            13.90
# Bronze      592   1,167            26.85
# Bronze      611   1,209            27.30
# Bronze      591   1,212            27.85
# Bronze      455   1,212            30.90
# Bronze      142     931            29.26
# Bronze       73     932            31.22
# Bronze      102     929            30.45
# Bronze       45     927            32.00
# Silver      528     560            12.00
# Silver      402     555            15.53
# Silver      406     557            15.36
# Silver      284     556            17.43
# Silver      258     558            17.81
# Silver      165     558            19.88
# Silver      174     555            19.81
# Silver      169     566            20.25
# Silver       99     577            22.07
# Silver      129     586            21.68
# Silver      150     588            21.27
# Silver      126     590            21.85
# Silver       44     590            24.29
# Gold        342     426            18.35
# Gold        376     429            17.08
# Gold        330     453            18.70
# Gold        223     455      260   21.58
# Gold        162     456      199   23.33

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
    wait
  end
end

class ScanSectorTask < Task
  def initialize(state, bot)
    super state, bot
    @rand_target = around_next_radar
  end

  def around_next_radar
    return unless (target = @gs.available_radar_pos)

    drow = rand(-4..4)
    dcol = rand((-4 + drow.abs)..(4 - drow.abs))
    Position.new(target.row + drow, target.col + dcol)
  end

  def next_command
    target = @gs.nearest_ore(@bot)&.pos || @rand_target
    return finish_by { wait } if target.nil?

    if @bot.can_dig? target
      finish_by { dig_at target }
    else
      move_to target
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
    return finish_by { wait } if target.nil?

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
    super || @bot.at_hq?
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

class SuicideTask < Task
  def initialize(state, bot, target)
    super state, bot
    @target = target
  end

  def next_command
    finish_by { dig_at @target }
  end
end

class Cell
  attr_accessor :dangerous
  attr_reader :ore, :hole, :pos, :entities, :just_digged

  def initialize(pos)
    @pos = pos
    @ore = nil
    @hole = :none
    @just_digged = false
  end

  def entity=(entity)
    @entities = @entities.nil? ? [entity] : @entities << entity
  end

  def set_state(ore, hole)
    @just_digged = false
    if ore != '?'
      ore = ore.to_i
      @just_digged = true if @ore && @ore > ore
      @ore = ore
    end
    if !hole? && hole == '1'
      @hole = :opponent
      @just_digged = true
    end
    @entities = nil
  end

  def claim_hole
    @hole = :player
  end

  def hole?
    @hole != :none
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

  def robots?
    return @entities&.any?(&:robot?) unless block_given?

    @entities&.each do |ent|
      yield ent if ent.robot?
    end
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
            @dangerous ? '!' : ' '
          elsif @entities.size > 1
            @entities.size
          else
            @entities.first.to_s
          end
    ore = case @hole
          when :player
            @ore ? %w[O A B C D E F][@ore] : 'H'
          when :opponent
            @ore ? %w[° a b c d e f][@ore] : 'h'
          else
            @ore&.zero? ? '_' : @ore || '.'
          end
    "#{ore}#{ent}"
  end
end

class Board
  def initialize
    @cells = Array.new(HEIGHT) { |row| Array.new(WIDTH) { |col| Cell.new(Position.new(row, col)) } }
    @ores = []
  end

  def [](pos = nil, row: pos.row, col: pos.col)
    @cells[row]&.[](col)
  end

  def ore(pos)
    self[pos].ore
  end

  def hole(pos)
    self[pos].hole
  end

  def each_neighbour(pos, range: 1, &block)
    self[pos].tap(&block)
    (1..range).each do |delta|
      self[row: pos.row + delta, col: pos.col]&.tap(&block)
      self[row: pos.row - delta, col: pos.col]&.tap(&block)
      self[row: pos.row, col: pos.col + delta]&.tap(&block)
      self[row: pos.row, col: pos.col - delta]&.tap(&block)
    end
  end

  def nearest_ore_list(min_size: 1, max_size: 99)
    @ores.select { |cell| cell.ore.between?(min_size, max_size) && !cell.trap? && !cell.dangerous }
    # @ores.select { |cell| cell.ore.between?(min_size, max_size) && !cell.trap? } if list.empty?
  end

  def nearest_ore(pos, min_size: 1, max_size: 99)
    nearest_ore_list(min_size: min_size, max_size: max_size).min_by { |cell| pos.distance_to cell.pos }
  end

  def decrement_ore(pos, clear: false)
    cell = self[pos]
    cell.decrement_ore clear: clear
    @ores.delete(cell) unless cell.contains_ore?
  end

  def ore_count
    nearest_ore_list.map(&:ore).sum
  end

  def all_dangerous
    danger = []
    (0...HEIGHT).each do |row|
      (0...WIDTH).each do |col|
        cell = self[row: row, col: col]
        danger << cell if cell.dangerous
      end
    end
    danger
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

  def robot?
    false
  end
end

class Robot < Entity
  attr_reader :pos, :item, :owner
  attr_accessor :task

  def initialize(id, col, row, item_id, owner)
    super id, col, row
    @item = item_id.to_item
    @owner = %i[player opponent][owner]
    @last_pos = @pos
    @last_cmd = nil
    @carry = false
    @dropped = false
  end

  def update(col, row, item_id)
    @last_pos = @pos
    if row.negative?
      @pos = nil
      @item = :none
    else
      @pos = Position.new(row, col)
      @item = item_id.to_item
      @dropped = false
      if @pos == @last_pos
        @dropped = @carry && !at_hq?
        @carry = at_hq?
      end
    end
    self
  end

  def robot?
    true
  end

  def distance_to(pos)
    @pos.distance_to pos
  end

  def nearest(pos1, pos2)
    distance_to(pos) < distance_to(pos2) ? pos1 : pos2
  end

  def mine?
    if block_given?
      yield if @owner == :player
    else
      @owner == :player
    end
  end

  def disabled?
    @pos.nil?
  end

  def enabled?
    !disabled?
  end

  def carrying?(item = nil)
    item.nil? ? @item != :none : @item == item
  end

  def carrying_ore?
    @item == :ore
  end

  def can_dig?(pos)
    @pos == pos ||
      @pos.col == pos.col && (@pos.row - pos.row).abs <= 1 ||
      @pos.row == pos.row && (@pos.col - pos.col).abs <= 1
  end

  def mark_dangerous(board)
    return if disabled? || !@dropped

    marked = 0
    board.each_neighbour(@pos) do |cell|
      if cell.just_digged && cell.hole == :opponent
        cell.dangerous = true
        marked += 1
      end
    end

    return if marked.positive?

    board.each_neighbour(@pos) do |cell|
      cell.dangerous |= cell.hole?
    end
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
    case @owner
    when :player
      carrying? ? 'R' : 'r'
    else
      @carry ? 'S' : 's'
    end
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
  Position.new(7, 8),
  Position.new(2, 12),
  Position.new(12, 12),

  Position.new(2, 4),
  Position.new(12, 4),

  Position.new(7, 15),
  Position.new(2, 19),
  Position.new(12, 19),

  Position.new(7, 23),
  Position.new(2, 27),
  Position.new(12, 27),

  Position.new(7, 27)
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
      @msg = '' unless DEBUG
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
    @board.decrement_ore(target)
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
        (@robots[id] = @robots[id]&.update(col, row, item_id) || Robot.new(id, col, row, item_id, type))
          .tap { |bot| bot.mark_dangerous(@board) unless bot.mine? }
      when 2
        @items[id] = Radar.new(id, col, row)
      when 3
        @items[id] = Trap.new(id, col, row)
      end.tap { |entity| @board[entity.pos].entity = entity if entity.pos }
    end

    @my_bots = @robots.map(&:last).select(&:mine?)
  end

  def [](pos)
    @board[pos]
  end

  def radar_available?
    @radar_cooldown.zero?
  end

  def available_radar_pos
    RADAR_LOCATIONS.find do |pos|
      cell = @board[pos]
      !(cell.dangerous || cell.contains_item_type?(Radar))
    end
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

  def placing_radar_count
    @my_bots.count { |bot| bot.enabled? && bot.task.is_a?(PlaceRadarTask) }
  end

  def radar_bot
    @my_bots.find { |bot| bot.task.is_a? PlaceRadarTask }
  end

  def all_traps
    @items.values.select { |item| item.is_a? Trap }.map(&:pos) + @board.all_dangerous.map(&:pos)
  end

  def trap_kills(pos, kills = { player: [], opponent: [] }, visited = {})
    @board.each_neighbour(pos) do |cell|
      next if visited[cell.pos]

      visited[cell.pos] = true
      cell.robots? { |bot| kills[bot.owner] << bot if bot.enabled? }
      kills = trap_kills(cell.pos, kills, visited) if cell.trap?
    end
    kills
  end

  def kamikazes
    bots = {}
    all_traps.each do |pos|
      kills = trap_kills(pos)
      plys = kills[:player]
      opos = kills[:opponent]
      bots[plys.first.id] = pos if plys.size == 1 && opos.size >= 1 && plys.none?(&:carrying_ore?)
    end
    bots
  end

  def assign_tasks
    radar_avail = can_place_radar? && !radar_bot
    trap_avail = trap_available?
    kamis = kamikazes
    @my_bots.each do |bot|
      if kamis[bot.id]
        bot.task = SuicideTask.new(self, bot, kamis[bot.id])
        next
      end

      next unless bot.finished_task?

      if bot.enabled?
        ore_cell = nearest_ore(bot)
        ore_dist = ore_cell&.distance_to(bot.pos) || 999
      end

      # warn "bot: #{bot} => ore: #{ore_cell} @ #{ore_cell&.pos}"

      bot.task = if bot.disabled?
                   NoTask.new self, bot
                 elsif bot.carrying? :ore
                   DeliverOreTask.new(self, bot)
                 elsif radar_avail && ore_dist > 4
                   PlaceRadarTask.new(self, bot).tap { radar_avail = false }
                 elsif bot.at_hq? && trap_avail && nearest_ore(bot, min_size: 2) && ore_dist > 4
                   PlaceTrapTask.new(self, bot).tap { |tsk| @board.decrement_ore(tsk.target, clear: true); trap_avail = false }
                 elsif ore_cell
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
    # @board.to_s
    s = ''
    @items.each do |_, item|
      if item.is_a? Trap
        kills = trap_kills(item.pos)
        s << "#{item.pos} => #{kills}" if kills[:player].size == 1 && kills[:opponent].size.positive?
      end
    end
    s
  end
end

# game loop
gs = GameState.new

loop do
  gs.read_state
  warn gs if DEBUG
  puts gs.moves
end
