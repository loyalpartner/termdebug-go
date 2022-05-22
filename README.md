termdebug-go
============

[![Build Status](https://app.travis-ci.com/loyalpartner/termdebug-go.svg?branch=main)](https://app.travis-ci.com/loyalpartner/termdebug-go)

The geeks's debug tool for golang users.

This plugin is inspired [termdebug.vim](https://github.com/vim/vim/blob/master/runtime/pack/dist/opt/termdebug/plugin/termdebug.vim).

## Deps
[delve](https://github.com/go-delve/delve) 

```
go install github.com/go-delve/delve/cmd/dlv@latest
```

![display](./images/display.gif)


# TODO:
- restore state after exit
1. save breakpoints
2. show local variables
3. show backtrace
4. show logs
