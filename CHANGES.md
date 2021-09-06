v0.1: Initial Release

v0.1.1:  
- customizable initial size for internal buffer
- remove single lwt related function and lwt dependency

v0.2:  
- CI tests
- error management improvements (use result, allow exn and option)
- do not print 0-sized fields in binary descriptions

v0.3:  
- Adapt to json-data-encoding.0.9.1 and provide json-lexeme seq to string seq
- Improved performance
- `maximum_length` to determine static size bounds (when possible)
- provide `to_`/`of_string` alongside `to_`/`of_bytes`
- Improved documentation
- Increase test coverage
- Fix JSON encoding of Result

v0.4:  
- catch exceptions in user-provided functions
- provide `conv_guard` to help enforce invariants
- remove unused `read_error` constructor: `Invalid_size`
- check that `int31` is actually within `int31` bounds
- add "slicing" feature to analyse binary encoded values
- add a default argument to `Json.construct`: `?include_default_fields`,
  which is simply passed on to `Json_encoding.construct`