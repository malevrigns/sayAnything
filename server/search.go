package main

import (
	"database/sql/driver"
	"strings"

	"modernc.org/sqlite"
)

func init() {
	// SQLite lower() only handles ASCII. Go's Unicode lowercase mapping keeps
	// nickname/body searches consistent with the client's previous behavior.
	// It maps one rune to one rune, preserving positions in original snippets.
	sqlite.MustRegisterDeterministicScalarFunction("sayanything_lower", 1,
		func(_ *sqlite.FunctionContext, args []driver.Value) (driver.Value, error) {
			if args[0] == nil {
				return nil, nil
			}
			return strings.ToLower(args[0].(string)), nil
		})
}
