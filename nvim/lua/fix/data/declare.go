package data

type Thing struct{}

// a field to test member-access matching: something undefined used as x.VerificationID
// should match by "has this field", not by whatever type the surrounding call expects
type Request struct {
	VerificationID string
}

// the real declaration a cross-file rename points at — reached via workspace search
func FetchUserByID(id string) (string, error) {
	return id, nil
}

// a multi-return function to test assignment-type matching: the LHS of := should be
// matchable by this return type, same as member access is matched by field type.
func Lookup() (Request, error) {
	return Request{}, nil
}
