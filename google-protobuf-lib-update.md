The google protobuf gem has [not been updated for jruby in a while](https://github.com/protocolbuffers/protobuf/issues/1594) and is currently only available in version [3.5.0.pre](https://rubygems.org/gems/google-protobuf/versions/3.5.0.pre-java) whereas the official protobuf version is 3.18+.
If you want to use a newer library version then please follow these instructions on how to manually build the google-protobuf.gem.

0.  Get the protobuf sources:
```
git clone https://github.com/protocolbuffers/protobuf.git;
cd protobuf;
git checkout $VERSION_YOU_WANT_TO_BUILD
```

1. Check your compiler version. It needs to be at least the version that you want to build for.
`protoc --version`

If your compiler is too old, build it from the repo:

```
git submodule update --init --recursive
./autogen.sh
./configure
make
make check
sudo make install
```

(instructions taken from their [src/README.md](https://github.com/protocolbuffers/protobuf/blob/master/src/README.md) - check for updates in there!)

2. Build the gem:
`cd ruby; rake build && gem build *.gemspec`

(Instructions taken from https://github.com/protocolbuffers/protobuf/issues/1594#issuecomment-258029377)

3. Change the dependency in the protobuf codec:

Step 3.a: clone this repo.
`git clone git@github.com:logstash-plugins/logstash-codec-protobuf.git`

Step 3.b: edit the dependency in [the gemspec](https://github.com/logstash-plugins/logstash-codec-protobuf/blob/master/logstash-codec-protobuf.gemspec#L23) to the version that you built in step 2.

Step 3.c: set the [codec version in the gemspec](https://github.com/logstash-plugins/logstash-codec-protobuf/blob/master/logstash-codec-protobuf.gemspec#L4) to a number that is not available on rubygems.

Step 3.d: build the codec. `rake build && gem build logstash-codec-protobuf.gemspec`


4. Install both gems in your Logstash (in this order):
```
logstash-plugin install --no-verify google-protobuf-$PROTOBUF_GEM_VERSION-java.gem
logstash-plugin install logstash-codec-protobuf-$PROTOBUF_INPUT_PLUGIN_VERSION.gem
```

# Notes

We experimented with both the `>= ` and the `~>` operators in the dependency specification, such as
` s.add_runtime_dependency 'google-protobuf', '>= 3.5.0.pre`
but it would always lead to the ruby version of the protobuf gem to be pulled. Hints / PRs for pinning this to the Java/Jruby version would be appreciated and would render the steps in section 3 and parts of step 4 unnecessary.

