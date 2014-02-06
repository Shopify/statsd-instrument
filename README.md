# StatsD client for Ruby apps

[![Built on Travis](https://secure.travis-ci.org/Shopify/statsd-instrument.png?branch=master)](https://secure.travis-ci.org/Shopify/statsd-instrument)

This is a ruby client for statsd (http://github.com/etsy/statsd). It provides a lightweight way to track and measure metrics in your application. 

We call out to statsd by sending data over a UDP socket. UDP sockets are fast, but unreliable, there is no guarantee that your data will ever arrive at it's location. In other words, fire and forget. This is perfect for this use case because it means your code doesn't get bogged down trying to log statistics. We send data to statsd several times per request and haven't noticed a performance hit.

The fact that all of your stats data may not make it into statsd is no issue. Graphite (the graph database that statsd is built on) will only show you trends in your data. Internally it only keeps enough data to satisfy the levels of granularity we specify. As well as satisfying it's requirement as a fixed size database. We can throw as much data at it as we want it and it will do it's best to show us the trends over time and get rid of the fluff.

For Shopify, our retention periods are:

1. 10 seconds of granularity for the last 6 hours
2. 60 seconds of granularity for the last week
3. 10 minutes of granularity for the last 5 years

This is the same as what Etsy uses (mentioned in the README for http://github.com/etsy/statsd).

## Configuration

``` ruby
# The UDP endpoint to which you want to submit your metrics.
# This is set to the environment variable STATSD_ADDR if it is set.
StatsD.server = 'statsd.myservice.com:8125' 

# Events are only actually submitted in production mode. For any other value, thewy are logged instead
# This value is set by to the value of the RAILS_ENV or RACK_ENV environment variable if it is set.
StatsD.mode = :production

# Logger to which commands are logged when not in :production mode.
# In  production only errors are logged to the console.
StatsD.logger = Rails.logger

# An optional prefix to be added to each stat.
StatsD.prefix = 'my_app' 

# Sample 10% of events. By default all events are reported, which may overload your network or server.
# You can, and should vary this on a per metric basis, depending on frequency and accuracy requirements
StatsD.default_sample_rate = 0.1 


```

There are several implementations of StatsD out there, all with slight protocol variations. You can this library to use the proper protocol by informing it about what implementation you use. By default, it will use the `STATSD_IMPLEMENTATION` environment variable, if it is not set it will use the protocol of the original Etsy implementation.

```
StatsD.implementation = :datadog  # Enable datadog extensions: tags and histograms
StatsD.implementation = :statsite # Enable keyvalue-style gauges 
```

## StatsD keys

StatsD keys look like 'admin.logins.api.success'. Each dot in the key represents a 'folder' in the graphite interface. You can include any data you want in the keys.

## Usage

You can either use the basic methods to submit stats over StatsD, or you can use the metaprogramming methods to instrument your methods with some basic stats (call counts, successes & failures, and timings).

#### StatsD.measure

Lets you benchmark how long the execution of a specific method takes.

``` ruby
# You can pass a key and a ms value
StatsD.measure('GoogleBase.insert', 2.55)

# or more commonly pass a block that calls your code
StatsD.measure('GoogleBase.insert') do
  GoogleBase.insert(product)
end
```
		
#### StatsD.increment

Lets you increment a key in statsd to keep a count of something. If the specified key doesn't exist it will create it for you.

``` ruby
# increments default to +1
StatsD.increment('GoogleBase.insert')
# you can also specify how much to increment the key by
StatsD.increment('GoogleBase.insert', 10)
# you can also specify a sample rate, so only 1/10 of events
# actually get to statsd. Useful for very high volume data
StatsD.increment('GoogleBase.insert', 1, 0.1)
```

#### StatsD.gauge

A gauge is a single numerical value value that tells you the state of the system at a point in time. A good example would be the number of messages in a queue.

``` ruby
StatsD.gauge('GoogleBase.queued', 12, 1.0)
```

Normally, you shouldn't update this value too often, and therefore there is no need to sample this kind metric.

#### StatsD.set

A set keeps track of the number of unique values that have been seen. This is a good fit for keeping track of the number of unique visitors. The value can be a string.

``` ruby
# Submit the customer ID to the set. It will only be counted if it hasn't been seen before.
StatsD.set('GoogleBase.customers', "12345", 1.0)
```

Because you are counting unique values, the results of using a sampling value less than 1.0 can lead to unexpected, hard to interpret results.

### Metaprogramming Methods

As mentioned, it's most common to use the provided metaprogramming methods. This lets you define all of your instrumentation in one file and not litter your code with instrumentation details. You should enable a class for instrumentation by extending it with the `StatsD::Instrument` class.

``` ruby
GoogleBase.extend StatsD::Instrument
```

Then use the methods provided below to instrument methods in your class.

#### statsd\_measure

This will measure how long a method takes to run, and submits the result to the given key.

``` ruby
GoogleBase.statsd_measure :insert, 'GoogleBase.insert'
```

#### statsd\_count

This will increment the given key even if the method doesn't finish (ie. raises).

``` ruby
GoogleBase.statsd_count :insert, 'GoogleBase.insert'
```

Note how I used the 'GoogleBase.insert' key above when measuring this method, and I reused here when counting the method calls. StatsD automatically separates these two kinds of stats into namespaces so there won't be a key collision here.

#### statsd\_count\_if

This will only increment the given key if the method executes successfully.

``` ruby
GoogleBase.statsd_count_if :insert, 'GoogleBase.insert'
```

So now, if GoogleBase#insert raises an exception or returns false (ie. result == false), we won't increment the key. If you want to define what success means for a given method you can pass a block that takes the result of the method.

``` ruby
GoogleBase.statsd_count_if :insert, 'GoogleBase.insert' do |response|
  response.code == 200
end
```

In the above example we will only increment the key in statsd if the result of the block returns true. So the method is returning a Net::HTTP response and we're checking the status code.

#### statsd\_count\_success

Similar to statsd_count_if, except this will increment one key in the case of success and another key in the case of failure.

``` ruby
GoogleBase.statsd_count_success :insert, 'GoogleBase.insert'
```

So if this method fails execution (raises or returns false) we'll increment the failure key ('GoogleBase.insert.failure'), otherwise we'll increment the success key ('GoogleBase.insert.success'). Notice that we're modifying the given key before sending it to statsd.

Again you can pass a block to define what success means.

``` ruby
GoogleBase.statsd_count_success :insert, 'GoogleBase.insert' do |response|
  response.code == 200
end
```

### Instrumenting Class Methods

You can instrument class methods, just like instance methods, using the metaprogramming methods. You simply have to configure the instrumentation on the singleton class of the Class you want to instrument.

```ruby
AWS::S3::Base.singleton_class.extend StatsD::Instrument
AWS::S3::Base.singleton_class.statsd_measure :request, 'S3.request'
```

### Dynamic Metric Names

You can use a lambda function instead of a string dynamically set
the name of the metric. The lambda function must accept two arguments:
the object the function is being called on and the array of arguments
passed.

```ruby
GoogleBase.statsd_count :insert, lamdba{|object, args| object.class.to_s.downcase + "." + args.first.to_s + ".insert" }
```

## Reliance on DNS

Out of the box StatsD is set up to be unidirectional fire-and-forget over UDP. Configuring the StatsD host to be a non-ip will trigger a DNS lookup (ie synchronous round trip network call) for each metric sent. This can be particularly problematic in clouds that have a shared DNS infrastructure such as AWS.

### Common Workarounds

1. Using an IP avoids the DNS lookup but generally requires an application deploy to change.
2. Hardcoding the DNS/IP pair in /etc/hosts allows the IP to change without redeploying your application but fails to scale as the number of servers increases.
3. Installing caching software such as nscd that uses the DNS TTL avoids most DNS lookups but makes the exact moment of change indeterminate.

## Compatibility

Tested on several Ruby versions using Travis CI:

* Ruby 1.8.7
* Ruby Enterprise Edition 1.8.7
* Ruby 1.9.3
* Ruby 2.0.0
* Ruby 2.1.0

## Contributing

This project is MIT licensed and welcomes outside contributions.

1. Fork the repository, and create a feature branch.
2. Implement the feature, and add tests that cover the new changes functionality.
3. Update the README.
4. Create a pull request. Make sure that you get a CI pass on it.
5. Ping @jstorimer and/or @wvanbergen for review.
