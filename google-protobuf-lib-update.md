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

3. Install the new gem in your Logstash:
```
logstash-plugin install --no-verify google-protobuf-$PROTOBUF_GEM_VERSION-java.gem
```

4. Make sure that you use at least version 1.2.6 or higher of the logstash-codec-protobuf.