// Package parsers converts raw MapReduce TSV output into typed risk structs.
package parsers

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/aadityaa/hadoop-risk/result-aggregator/models"
)

// ParseGradeResults parses the TSV output of Job 1 (default rate by loan grade).
// Each line format: <grade>\t<total>\t<defaults>\t<default_rate_pct>
func ParseGradeResults(raw string) ([]models.LoanGradeRisk, error) {
	var results []models.LoanGradeRisk
	for _, line := range splitLines(raw) {
		parts := strings.Split(line, "\t")
		if len(parts) != 4 {
			continue
		}
		total, err1 := strconv.Atoi(strings.TrimSpace(parts[1]))
		defaults, err2 := strconv.Atoi(strings.TrimSpace(parts[2]))
		rate, err3 := strconv.ParseFloat(strings.TrimSpace(parts[3]), 64)
		if err1 != nil || err2 != nil || err3 != nil {
			return nil, fmt.Errorf("grade parse error on line %q: %v %v %v", line, err1, err2, err3)
		}
		grade := strings.TrimSpace(parts[0])
		results = append(results, models.LoanGradeRisk{
			Grade:       grade,
			TotalLoans:  total,
			Defaults:    defaults,
			DefaultRate: rate,
			RiskLevel:   models.ClassifyRisk(rate),
		})
	}
	return results, nil
}
