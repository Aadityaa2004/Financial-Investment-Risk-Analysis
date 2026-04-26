package parsers

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/aadityaa/hadoop-risk/result-aggregator/models"
)

// ParseStateResults parses the TSV output of Job 2 (default rate by US state).
// Each line format: <state>\t<total>\t<defaults>\t<default_rate_pct>
func ParseStateResults(raw string) ([]models.StateRisk, error) {
	var results []models.StateRisk
	for _, line := range splitLines(raw) {
		parts := strings.Split(line, "\t")
		if len(parts) != 4 {
			continue
		}
		total, err1 := strconv.Atoi(strings.TrimSpace(parts[1]))
		defaults, err2 := strconv.Atoi(strings.TrimSpace(parts[2]))
		rate, err3 := strconv.ParseFloat(strings.TrimSpace(parts[3]), 64)
		if err1 != nil || err2 != nil || err3 != nil {
			return nil, fmt.Errorf("state parse error on line %q: %v %v %v", line, err1, err2, err3)
		}
		state := strings.TrimSpace(parts[0])
		results = append(results, models.StateRisk{
			State:       state,
			TotalLoans:  total,
			Defaults:    defaults,
			DefaultRate: rate,
			RiskLevel:   models.ClassifyRisk(rate),
		})
	}
	return results, nil
}
