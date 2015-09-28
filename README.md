# Aggregate Trace Spike
========

## tracecollapse.rb - an approach to printing summary information on a corpus of traces from Zipkin

### Setup
Assuming you are using rvm, just do a ```gem install bundler``` if necessary, and then ```bundle```. Other scenarios left as exercise for the reader. Only tested with ruby-2.2.1

### Usage

This just operates on a corpus of JSON traces on local disk. For ease of use, we expect them to be in a directory:
```
./tracecollapse.rb path/to/a/corpus/of/traces
```

### Getting Data
If you have a trace id, you can get a trace from zipkin thusly:
```
curl -s "http://ZIPKIN_HOST:PORT/api/get/TRACE_ID" -o some_dir/TRACE_ID.json
```

Looping left as an exercise for the reader.

### Caveats

This code is heinous. It was a quick spike for a proof-of-concept. We know it's gross. This code is a case study in the horror of mutation.

### License

MIT. See LICENSE file.
