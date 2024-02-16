# Ruzzy

[![Test](https://github.com/trailofbits/ruzzy/actions/workflows/test.yml/badge.svg)](https://github.com/trailofbits/ruzzy/actions/workflows/test.yml)
[![Gem Version](https://img.shields.io/gem/v/ruzzy)](https://rubygems.org/gems/ruzzy)

A coverage-guided fuzzer for both pure Ruby code and Ruby [C extensions](https://ruby-doc.org/3.3.0/extension_rdoc.html).

Ruzzy is heavily inspired by Google's [Atheris](https://github.com/google/atheris), a Python fuzzer. Like Atheris, Ruzzy uses [libFuzzer](https://llvm.org/docs/LibFuzzer.html) for its coverage instrumentation and fuzzing engine. Ruzzy also supports [AddressSanitizer](https://clang.llvm.org/docs/AddressSanitizer.html) and [UndefinedBehaviorSanitizer](https://clang.llvm.org/docs/UndefinedBehaviorSanitizer.html) when fuzzing C extensions.

Table of contents:

- [Installing](#installing)
- [Using](#using)
  - [Getting started](#getting-started)
  - [Fuzzing pure Ruby code](#fuzzing-pure-ruby-code)
  - [Fuzzing Ruby C extensions](#fuzzing-ruby-c-extensions)
- [Developing](#developing)
  - [Compiling](#compiling)
  - [Testing](#testing)
  - [Linting](#linting)
  - [Releasing](#releasing)
- [Further reading](#further-reading)

# Installing

Currently, Ruzzy only supports Linux x86-64 and AArch64/ARM64. If you'd like to run Ruzzy on a Mac or Windows, you can build the [`Dockerfile`](https://github.com/trailofbits/ruzzy/blob/main/Dockerfile) and/or use the [development environment](#developing). Ruzzy requires a recent version of `clang`, preferably the [latest release](https://github.com/llvm/llvm-project/releases).

Install Ruzzy with the following command:

```bash
MAKE="make --environment-overrides V=1" \
CC="/path/to/clang" \
CXX="/path/to/clang++" \
LDSHARED="/path/to/clang -shared" \
LDSHAREDXX="/path/to/clang++ -shared" \
    gem install ruzzy
```

There's a lot going on here, so let's break it down:

- The `MAKE` environment variable overrides the `make` command when compiling the Ruzzy C extension. This tells `make` to respect subsequent environment variables when compiling the extension.
- The rest of the environment variables are used during compilation to ensure we're using the proper `clang` binaries. This ensures we have the latest `clang` features, which are necessary for proper fuzzing.

If you run into issues installing, then you can run the following command to get debugging output:

```bash
RUZZY_DEBUG=1 gem install --verbose ruzzy
```

# Using

## Getting started

Ruzzy includes a [toy example](https://llvm.org/docs/LibFuzzer.html#toy-example) to demonstrate how it works. First, set the following environment variable:

```bash
export ASAN_OPTIONS="allocator_may_return_null=1:detect_leaks=0:use_sigaltstack=0"
```

<details>
<summary>Understanding these options isn't necessary, but if you're curious click here.</summary>

### `ASAN_OPTIONS`

1. Memory allocation failures are common and low impact (DoS), so skip them for now.
1. Like Python, the Ruby interpreter [leaks data](https://github.com/google/atheris/blob/master/native_extension_fuzzing.md#leak-detection), so ignore these for now.
1. Ruby recommends [disabling sigaltstack](https://github.com/ruby/ruby/blob/master/doc/contributing/building_ruby.md#building-with-address-sanitizer).

</details>

You can then run the example with the following command:

```bash
LD_PRELOAD=$(ruby -e 'require "ruzzy"; print Ruzzy::ASAN_PATH') \
    ruby -e 'require "ruzzy"; Ruzzy.dummy'
```

_`LD_PRELOAD` is required for the same reasons [as Atheris](https://github.com/google/atheris/blob/master/native_extension_fuzzing.md#option-a-sanitizerlibfuzzer-preloads). However, unlike `ASAN_OPTIONS`, you probably do not want to `export` it as it may interfere with other programs._

It should quickly produce a crash like the following:

```
INFO: Running with entropic power schedule (0xFF, 100).
INFO: Seed: 2527961537
==3==ERROR: AddressSanitizer: stack-use-after-return on address 0xffffa8000920 at pc 0xffffa96a1a58 bp 0xfffff04ddbb0 sp 0xfffff04ddba8
...
SUMMARY: AddressSanitizer: stack-use-after-return /var/lib/gems/3.1.0/gems/ruzzy-0.5.0/ext/dummy/dummy.c:18:24 in _c_dummy_test_one_input
...
==1541==ABORTING
MS: 2 ChangeByte-CrossOver-; base unit: b408860bc2c0584b8e0bb6fa3443005a3ef39854
0x48,0x49,
HI
artifact_prefix='./'; Test unit written to ./crash-253420c1158bc6382093d409ce2e9cff5806e980
Base64: SEk=
```

We can see that it correctly found the input (`"HI"`) that produced a memory violation. For more information, see [`dummy.c`](https://github.com/trailofbits/ruzzy/blob/main/ext/dummy/dummy.c) to see why this violation occurred.

You can re-run the crash case with the following command:

```bash
LD_PRELOAD=$(ruby -e 'require "ruzzy"; print Ruzzy::ASAN_PATH') \
    ruby -e 'require "ruzzy"; Ruzzy.dummy' \
    ./crash-253420c1158bc6382093d409ce2e9cff5806e980
```

The following sanitizers are available:

- `Ruzzy::ASAN_PATH` for [AddressSanitizer](https://clang.llvm.org/docs/AddressSanitizer.html)
- `Ruzzy::UBSAN_PATH` for [UndefinedBehaviorSanitizer](https://clang.llvm.org/docs/UndefinedBehaviorSanitizer.html)

## Fuzzing pure Ruby code

Let's fuzz a small Ruby script as an example. Fuzzing pure Ruby code requires two Ruby scripts: a tracer script and a fuzzing harness. The tracer script is required due to an implementation detail of the Ruby interpreter. Understanding the details of this interaction, other than the fact that it's necessary, is not required.

First, the tracer script, let's call it `test_tracer.rb`:

```ruby
# frozen_string_literal: true

require 'ruzzy'

Ruzzy.trace('test_harness.rb')
```

Next, the fuzzing harness, let's call it `test_harness.rb`:

```ruby
# frozen_string_literal: true

require 'ruzzy'

test_one_input = lambda do |data|
  if data.length == 4
    if data[0] == 'F'
      if data[1] == 'U'
        if data[2] == 'Z'
          if data[3] == 'Z'
            raise
          end
        end
      end
    end
  end
  return 0
end

Ruzzy.fuzz(test_one_input)
```

You can run this file and start fuzzing with the following command:

```bash
LD_PRELOAD=$(ruby -e 'require "ruzzy"; print Ruzzy::ASAN_PATH') \
    ruby test_tracer.rb
```

It should quickly produce a crash like the following:

```
INFO: Running with entropic power schedule (0xFF, 100).
INFO: Seed: 2311041000
...
/app/ruzzy/bin/test_harness.rb:12:in `block in <top (required)>': unhandled exception
	from /var/lib/gems/3.1.0/gems/ruzzy-0.6.0/lib/ruzzy.rb:15:in `c_fuzz'
	from /var/lib/gems/3.1.0/gems/ruzzy-0.6.0/lib/ruzzy.rb:15:in `fuzz'
	from /app/ruzzy/bin/test_harness.rb:35:in `<top (required)>'
	from bin/test_tracer.rb:7:in `require_relative'
	from bin/test_tracer.rb:7:in `<main>'
...
SUMMARY: libFuzzer: fuzz target exited
MS: 1 CopyPart-; base unit: 24b4b428cf94c21616893d6f94b30398a49d27cc
0x46,0x55,0x5a,0x5a,
FUZZ
artifact_prefix='./'; Test unit written to ./crash-aea2e3923af219a8956f626558ef32f30a914ebc
Base64: RlVaWg==
```

We can see that it correctly found the input (`"FUZZ"`) that produced an exception.

To fuzz your own target, modify the `test_one_input` `lambda` to call your target function.

## Fuzzing Ruby C extensions

Let's fuzz the [`msgpack-ruby`](https://github.com/msgpack/msgpack-ruby) library as an example. First, install the gem:

```bash
MAKE="make --environment-overrides V=1" \
CC="/path/to/clang" \
CXX="/path/to/clang++" \
LDSHARED="/path/to/clang -shared" \
LDSHAREDXX="/path/to/clang++ -shared" \
CFLAGS="-fsanitize=address,fuzzer-no-link -fno-omit-frame-pointer -fno-common -fPIC -g" \
CXXFLAGS="-fsanitize=address,fuzzer-no-link -fno-omit-frame-pointer -fno-common -fPIC -g" \
    gem install msgpack
```

In addition to the environment variables used when compiling Ruzzy, we're specifying `CFLAGS` and `CXXFLAGS`. These flags aid in the fuzzing process. They enable helpful functionality like an address sanitizer, and improved stack trace information. For more information see [AddressSanitizerFlags](https://github.com/google/sanitizers/wiki/AddressSanitizerFlags).

Next, we need a fuzzing harness for `msgpack`. The following may be familiar to those with [libFuzzer experience](https://llvm.org/docs/LibFuzzer.html#fuzz-target):

```ruby
# frozen_string_literal: true

require 'msgpack'
require 'ruzzy'

test_one_input = lambda do |data|
  begin
    MessagePack.unpack(data)
  rescue Exception
    # We're looking for memory corruption, not Ruby exceptions
  end
  return 0
end

Ruzzy.fuzz(test_one_input)
```

Let's call this file `fuzz_msgpack.rb`. You can run this file and start fuzzing with the following command:

```bash
LD_PRELOAD=$(ruby -e 'require "ruzzy"; print Ruzzy::ASAN_PATH') \
    ruby fuzz_msgpack.rb
```

libFuzzer options can be passed to the Ruby script like so:

```bash
LD_PRELOAD=$(ruby -e 'require "ruzzy"; print Ruzzy::ASAN_PATH') \
    ruby fuzz_msgpack.rb /path/to/corpus
```

See [libFuzzer options](https://llvm.org/docs/LibFuzzer.html#options) for more information.

To fuzz your own target, modify the `test_one_input` `lambda` to call your target function.

# Developing

Development can be done locally, or using the `Dockerfile` provided in this repository.

You can build the Ruzzy Docker image with the following command:

```bash
docker build --tag ruzzy .
```

_You may want to grab a cup of coffee, the initial build can take a while._

By default, this will build a Docker image for AArch64 architectures (e.g. M-series MacBooks). If you need to run Ruzzy on other architectures, like x86, you can use the following [build arguments](https://docs.docker.com/build/guide/build-args/):

```
docker build \
    --build-arg CLANG_ARCH=x86_64 \
    --build-arg CLANG_URL=https://github.com/llvm/llvm-project/releases/download/llvmorg-17.0.6/clang+llvm-17.0.6-x86_64-linux-gnu-ubuntu-22.04.tar.xz \
    --build-arg CLANG_CHECKSUM=884ee67d647d77e58740c1e645649e29ae9e8a6fe87c1376be0f3a30f3cc9ab3 \
    --tag ruzzy \
    .
```

Then, you can shell into the container using the following command:

```
docker run -it -v $(pwd):/app/ruzzy --entrypoint /bin/bash ruzzy
```

## Compiling

We use [`rake-compiler`](https://github.com/rake-compiler/rake-compiler) to compile Ruzzy's C extensions.

You can compile the C extensions within the container with the following command:

```bash
rake compile
```

## Testing

We use `rake` unit tests to test Ruby code.

You can run the tests within the container with the following command:

```bash
LD_PRELOAD=$(ruby -e 'require "ruzzy"; print Ruzzy::ASAN_PATH') \
    rake test
```

## Linting

We use `rubocop` to lint Ruby code.

You can run `rubocop` within the container with the following command:

```bash
rubocop
```

## Releasing

Ruzzy is automatically [released](https://github.com/trailofbits/ruzzy/actions/workflows/release.yml) to [RubyGems](https://rubygems.org/gems/ruzzy) when a new git tag is pushed.

To release a new version run the following commands:

```bash
git tag vX.X.X
```

```bash
git push --tags
```

# Further reading

- Ruby C extensions
  - https://guides.rubygems.org/gems-with-extensions/
  - https://www.rubyguides.com/2018/03/write-ruby-c-extension/
  - https://rubyreferences.github.io/rubyref/advanced/extensions.html
  - https://silverhammermba.github.io/emberb/c/
  - https://ruby-doc.org/3.3.0/extension_rdoc.html
  - https://ruby-doc.org/3.3.0/stdlibs/mkmf/MakeMakefile.html
  - https://github.com/flavorjones/ruby-c-extensions-explained
  - https://github.com/ruby/ruby/blob/v3_3_0/lib/mkmf.rb
- Ruby fuzzing
  - https://github.com/twistlock/kisaten
  - https://github.com/richo/afl-ruby
  - https://z2-2z.github.io/2024/jan/16/fuzzing-ruby-c-extensions-with-coverage-and-asan.html
  - https://bsidessf2018.sched.com/event/E6jC/fuzzing-ruby-and-c-extensions
- Atheris
  - https://github.com/google/atheris/blob/master/native_extension_fuzzing.md
  - https://security.googleblog.com/2020/12/how-atheris-python-fuzzer-works.html
  - https://github.com/google/atheris/blob/2.3.0/setup.py
  - https://github.com/google/atheris/blob/2.3.0/src/native/core.cc
  - https://github.com/google/atheris/blob/2.3.0/src/native/tracer.cc
  - https://github.com/google/atheris/blob/2.3.0/src/native/counters.cc
