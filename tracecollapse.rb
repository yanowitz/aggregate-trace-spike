#!/usr/bin/env ruby

# (c) 2015 by Jason Yanowitz <f@ug.ly> and Jon Pliske <jonpliske@gmail.com>
# released under the MIT License (should be in the github repo accompanying this file, also at
# https://github.com/yanowitz/aggregate-trace-spike/blob/master/LICENSE)
#
# THIS IS A SPIKE. WE DISAVOW ITS QUALITY ;)

require 'json'
require 'ostruct'
require 'sparkr'
require 'descriptive_statistics'
# for debugging:
require 'pry'
require 'awesome_print'

def stats( spans )
  spans.map(&:duration).descriptive_statistics
end

def percentile( target, spans )
  spans.map(&:duration).percentile(target)
end

def visit( node, aggregated_traces, depth, &block )
  block.call(node, aggregated_traces, depth)
  node.child_nodes.each do |child|
    visit( child, aggregated_traces, depth+1, &block )
  end
end

def walk( aggregated_traces, &block )
  visit( aggregated_traces.root_node, aggregated_traces, 0, &block )
end

def bucketize( number_of_buckets, min, max, spans )
  bucket_size = (max - min + 1) / number_of_buckets.to_f

  buckets = Array.new(number_of_buckets,0)

  spans.each do |span|
    duration = span.duration
    bucket_number = ((duration - min - 1) / bucket_size).to_i
    buckets[bucket_number] += 1
  end

  buckets
end

def print_aggregated_traces( aggregated_traces )
  total_aggregated_traces = aggregated_traces.total_aggregated
  puts "Total traces: #{total_aggregated_traces}"
  ap aggregated_traces.root_uris

  printf("%-45s %10s %10s %10s %10s %10s %10s %10s %10s %10s %10s %s\n", "name", "# per trace", "avg in ms", "stddev", "min", "max", "t50", "t75", "t90", "t99", "sparkline", "total spans")

  walk( aggregated_traces ) do | node, aggregated_traces, depth |
    begin
      statistics = stats(node.spans)
      latency = statistics[:mean]
      stddev = statistics[:standard_deviation]
      min = statistics[:min]
      max = statistics[:max]

      pct_times_appearing = node.spans.size.to_f / total_aggregated_traces
      t50 = percentile(50, node.spans)
      t75 = percentile(75, node.spans)
      t90 = percentile(90, node.spans)
      t99 = percentile(99, node.spans)

      last_colon_index = (node.name =~ /:([^:]+)$/)
      last_colon_index /= 4 # we don't need all that white space
      name = $1
      padded_node_name = ""
      last_colon_index.times { padded_node_name << " " }
      padded_node_name << name
      padded_node_name = padded_node_name[0..44]

      # Should we bucketize based on global min/max? ATM, we do it on a per-aggregated-span basis
      bucket_values = bucketize( 20, min, max, node.spans)
      sparkline = Sparkr.sparkline( bucket_values )

      printf("%-45s %10.2f %10.2f %10.2f %10.2f %10.2f %10.2f %10.2f %10.2f %10.2f %s %5d\n", padded_node_name, pct_times_appearing, latency, stddev, min, max, t50, t75, t90, t99, sparkline, node.spans.size)
    rescue => e
      p e
      p e.backtrace
      pry.binding
    end
  end
end

def add_span(aggregated_traces, trace_id, parent_id, node_name, simple_span)
  node = aggregated_traces.nodes_by_name[node_name]

  if node
    node.spans << simple_span
  else
    parent_node_name = aggregated_traces.span_id_to_node_name["#{trace_id}:#{parent_id}"]
    parent_node = aggregated_traces.nodes_by_name[parent_node_name]
    node = OpenStruct.new( name: node_name,
                           spans: [simple_span],
                           child_nodes: [],
                           parent: parent_node
                         )

    aggregated_traces.nodes_by_name[node_name] = node

    parent_node.child_nodes << node if parent_node
  end

  aggregated_traces.span_id_to_node_name["#{trace_id}:#{simple_span.id}"] = node_name
  node
end

def process_trace( json_trace, aggregated_traces )
  aggregated_traces.total_aggregated += 1

  trace_id = json_trace["trace"]["traceId"]

  json_trace["trace"]["spans"].each do |span|
    parent_id = span["parentId"]
    parent_node_name = aggregated_traces.span_id_to_node_name["#{trace_id}:#{parent_id}"]

    span_name = span["services"].sort.join("|")  # concat aliases in sorted order

    # We are using node_name as a the equality mechanism to determine
    # whether spans across traces should be aggregated (it's the
    # service_name + path_to_root node). This is just one (naive!) method of aggregation
    node_name = "#{parent_node_name}:#{span_name}"

    simple_span = OpenStruct.new( duration: span["duration"] / 1000.0, id: span["id"], trace_id: trace_id)#, raw: span)

    node = add_span(aggregated_traces, trace_id, parent_id, node_name, simple_span)
    aggregated_traces.root_node ||= node
    unless span["parentId"]
      uri = json_trace["trace"]["spans"][0]["binaryAnnotations"].find { |a| a["key"] == "http.uri" }
      if uri
        aggregated_traces.root_uris[uri["value"]] += 1
      end
    end
  end
end

aggregated_traces = OpenStruct.new( total_aggregated: 0, nodes_by_name: {}, span_id_to_node_name: {}, root_node: nil, root_uris: Hash.new(0) )

directory_of_traces = ARGV[0]
unless Dir.exists?(directory_of_traces)
  $stderr.puts "Usage: #{$0} /path/to/directory/of/traces/that/end/in/.json"
  exit 1
end

# process everything, populating aggregated_traces
Dir.glob("#{directory_of_traces}/**/*json").each do |filename|
  trace = JSON.parse( File.read( filename ) )

  process_trace( trace, aggregated_traces )
end

print_aggregated_traces( aggregated_traces )
