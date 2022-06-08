package client

import (
	"encoding/json"
	"strconv"
)

type UintStr uint64

func (i UintStr) MarshalJSON() ([]byte, error) {
	return json.Marshal(strconv.FormatUint(uint64(i), 10))
}

func (i *UintStr) UnmarshalJSON(b []byte) error {
	// Try string first
	var s string
	if err := json.Unmarshal(b, &s); err == nil {
		value, err := strconv.ParseInt(s, 10, 64)
		if err != nil {
			return err
		}
		*i = UintStr(value)
		return nil
	}

	// Fallback to number
	return json.Unmarshal(b, (*uint64)(i))
}

type Uint8Str uint8

func (i Uint8Str) MarshalJSON() ([]byte, error) {
	return json.Marshal(strconv.FormatUint(uint64(i), 10))
}

func (i *Uint8Str) UnmarshalJSON(b []byte) error {
	// Try string first
	var s string
	if err := json.Unmarshal(b, &s); err == nil {
		value, err := strconv.ParseInt(s, 10, 8)
		if err != nil {
			return err
		}
		*i = Uint8Str(value)
		return nil
	}

	// Fallback to number
	return json.Unmarshal(b, (*uint8)(i))
}
