## 1.3.0
  - Enforce XOR between options for one-of
  - fix incorrect detection of metadata for one-of fields
  - Update protobuf library to 3.23.4

## 1.2.10
  - Update gem platform to be "java" instead of "jruby" [#67](https://github.com/logstash-plugins/logstash-codec-protobuf/pull/67)

## 1.2.9
  - Fix decoding of structs

## 1.2.8
  - Update protobuf library to 3.22.2

## 1.2.7
  - TODO

## 1.2.6
  - [DOC] Fixed link format (from MD to asciidoc) [#61](https://github.com/logstash-plugins/logstash-codec-protobuf/pull/61)

## 1.2.5
  - Encoder bugfix: avoid pipeline crash if encoding failed.

## 1.2.4
  - Encoder bugfix: avoid pipeline crash if encoding failed.

## 1.2.3
  - Add oneof information to @metadata (protobuf version 3 only).

## 1.2.2
  - Add type conversion feature to encoder

## 1.2.1
  - Keep original data in case of parsing errors

## 1.2.0
  - Autoload all referenced protobuf classes
  - Fix concurrency issue when using multiple pipelines

## 1.1.0
  - Add support for protobuf3

## 1.0.4
  - Update gemspec summary

## 1.0.3
  - Fix some documentation issues

## 1.0.1
 - Speed improvement, better exception handling and code refactoring

## 1.0.0
 - Update to v5.0 API

## 0.1.2
 - First version of this plugin
