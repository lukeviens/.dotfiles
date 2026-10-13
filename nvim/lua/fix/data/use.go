package data

// a concrete string,string signature — mirrors the real bug's slog.String(key, value string)
func describe(key, value string) string { return key + value }

var otherString = "unrelated"

// member access: "req" is undefined, but it's not a bare call argument — it's the base of
// req.VerificationID, nested inside describe's call. The expected-argument-type question
// (what does describe's 2nd param want? "string") is the wrong one — that matches otherString
// too, which has nothing to do with req. The right question is "what type has a
// VerificationID field" — "request" should win instead.
func HandleMember(request Request) string {
	// assignment: "x" is undefined (plain "=", not ":=" — it has to already exist), and it's
	// the LHS of an assignment from Lookup(), whose first return type is Request —
	// "request" is the only in-scope name of that type, zero spelling overlap with "x".
	x, _ = Lookup()
	_ = x
	return describe("verification", req.VerificationID)
}

func Handle(clients Thing, happening string, id string) error {
	// spelling: "happening" is the real parameter, "happend" is a plain typo
	_ = happend

	// type compatibility: "clients" is the real parameter and the right type for accept's
	// argument; "c" doesn't exist, zero spelling overlap with "clients"
	accept(c)

	// workspace search: the real function is FetchUserByID, declared in declare.go —
	// "FetchIDUser" is a rename that reorders its own chunks
	_, err := FetchIDUser(id)
	return err
}

func accept(t Thing) {}
