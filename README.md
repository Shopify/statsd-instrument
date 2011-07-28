# StatsD client for Ruby apps

## Overview

This is a ruby client for statsd (http://github.com/etsy/statsd). It provides a lightweight way to track and measure metrics in your application. 

We call out to statsd by sending data over a UDP socket. UDP sockets are fast, but unreliable, there is no guarantee that your data will ever arrive at it's location. In other words, fire and forget. This is perfect for this use case because it means your code doesn't get bogged down trying to log statistics. We send data to statsd several times per request and haven't noticed a performance hit.

The fact that all of your stats data may not make it into statsd is no issue. Graphite (the graph database that statsd is built on) will only show you trends in your data. Internally it only keeps enough data to satisfy the levels of granularity we specify. As well as satisfying it's requirement as a fixed size database. We can throw as much data at it as we want it and it will do it's best to show us the trends over time and get rid of the fluff.

For Shopify, our retention periods are:

1. 10 seconds of granularity for the last 6 hours
2. 60 seconds of granularity for the last week
3. 10 minutes of granularity for the last 5 years

This is the same as what Etsy uses (mentioned in the README for [http://github.com/etsy/statd](http://github.com/etsy/statd])).

## Configuration

``` ruby
StatsD.server = 'statsd.myservice.com:8125'
StatsD.logger = Rails.logger
StatsD.mode = :production
```

If you set the mode to anything besides production then the library will print its calls to the logger, rather than sending them over the wire.

## StatsD keys

StatsD keys look like 'admin.logins.api.success'. Each dot in the key represents a 'folder' in the graphite interface. You can include any data you want in the keys.

## Usage

### StatsD.measure

Lets you benchmark how long the execution of a specific method takes.

``` ruby
# You can pass a key and a ms value
StatsD.measure('GoogleBase.insert', 2.55)

# or more commonly pass a block that calls your code
StatsD.measure('GoogleBase.insert') do
  GoogleBase.insert(product)
end
```

Rather than using this method directly it's more common to use the metaprogramming methods made available.

``` ruby
GoogleBase.extend StatsD::Instrument
GoogleBase.statsd_measure :insert, 'GoogleBase.insert'
```
		
### StatsD.increment

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

Again it's more common to use the metaprogramming methods.

## Metaprogramming Methods

As mentioned, it's most common to use the provided metaprogramming methods. This lets you define all of your instrumentation in one file and not litter your code with instrumentation details. You should enable a class for instrumentation by extending it with the `StatsD::Instrument` class.

``` ruby
GoogleBase.extend StatsD::Instrument
```

Then use the methods provided below to instrument methods in your class.

### statsd\_count

This will increment the given key even if the method doesn't finish (ie. raises).

``` ruby
GoogleBase.statsd_count :insert, 'GoogleBase.insert'
```

Note how I used the 'GoogleBase.insert' key above when measuring this method, and I reused here when counting the method calls. StatsD automatically separates these two kinds of stats into namespaces so there won't be a key collision here.

### statsd\_count\_if

This will only increment the given key if the method executes successfully.

``` ruby
GoogleBase.statsd_count_if :insert, 'GoogleBase.insert'
```

So now, if GoogleBase#insert raises an exception or returns false (ie. result == false), we won't increment the key. If you want to define what success means for a given method you can pass a block that takes the result of the method.

``` ruby
GoogleBase.statsd_count_if :insert, 'GoogleBase.insert' do |response|
  result.code == 200
end
```

In the above example we will only increment the key in statsd if the result of the block returns true. So the method is returning a Net::HTTP response and we're checking the status code.

### statsd\_count\_success

Similar to statsd_count_if, except this will increment one key in the case of success and another key in the case of failure.

``` ruby
GoogleBase.statsd_count_success :insert, 'GoogleBase.insert'
```

So if this method fails execution (raises or returns false) we'll increment the failure key ('GoogleBase.insert.failure'), otherwise we'll increment the success key ('GoogleBase.insert.success'). Notice that we're modifying the given key before sending it to statsd.

Again you can pass a block to define what success means.

``` ruby
GoogleBase.statsd_count_if :insert, 'GoogleBase.insert' do |response|
  result.code == 200
end
```

