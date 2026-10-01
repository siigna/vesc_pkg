# dash_common_lua

The shared dash, ported from LispBM to Lua, for firmware built with
`-DSCRIPT_ENGINE=lua`.

Alongside `dash_common/` rather than replacing it: the lisp dash works, is on
hardware, and is the reference this port is checked against. Both will exist
until this one has run a full ride.

## Shape

The lisp dash keeps its state in globals -- `config-battery-cells`,
`stats-vin` -- which a single flat namespace makes workable. Lua has modules,
so the same state lives in two tables:

    config   board constants, provided by the board package
    state    live values, written by the stats thread

A lib reads them rather than taking twelve arguments, which keeps the call
sites as short as the lisp ones. `require` resolves through the packer, so a
module is a file and nothing needs registering.

## Tests

`test/run.sh` runs the unit tests against a host Lua. They are ports of the
cases in `dash_common/test`, asserting the same numbers, so a disagreement
between the two dashes shows up as a failing check rather than as a wrong
reading on a bike.

The host Lua is 64-bit where the firmware's is `LUA_32BITS`. For these
modules that is arithmetic on fractions well inside both, and the tolerance
is 0.001; anything sensitive to the difference belongs in the on-target
tests instead.
