class Reline::History < Array
  def initialize(config)
    @config = config
  end

  def to_s
    'HISTORY'
  end

  def delete_at(index)
    index = check_index(index)
    super(index)
  end

  def [](index)
    index = check_index(index) unless index.is_a?(Range)
    super(index)
  end

  def []=(index, val)
    index = check_index(index)
    super(index, String.new(val, encoding: Reline.encoding_system_needs))
  end

  def concat(*val)
    val.each do |v|
      push(*v)
    end
  end

  def push(*val)
    # If history_size is zero, all histories are dropped.
    return self if @config.history_size.zero?
    diff = size + val.size - @config.history_size
    if diff > 0
      if diff <= size
        shift(diff)
      else
        diff -= size
        clear
        val.shift(diff)
      end
    end
    super(*(val.map{ |v| String.new(v, encoding: Reline.encoding_system_needs) }))
  end

  def <<(val)
    # If history_size is zero, all histories are dropped.
    return self if @config.history_size.zero?
    shift if size + 1 > @config.history_size
    super(String.new(val, encoding: Reline.encoding_system_needs))
  end

  private def check_index(index)
    index += size if index < 0
    raise RangeError.new("index=<#{index}>") if index < -@config.history_size or @config.history_size < index
    raise IndexError.new("index=<#{index}>") if index < 0 or size <= index
    index
  end
end
