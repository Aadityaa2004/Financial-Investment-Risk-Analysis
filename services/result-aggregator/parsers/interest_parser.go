package parsers

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/aadityaa/hadoop-risk/result-aggregator/models"
)

// ParseInterestResults parses the TSV output of Job 4 (interest rate vs default rate by grade).
// Each line format: <grade>\t<total>\t<avg_interest_rate>\t<default_rate_pct>
func ParseInterestResults(raw string) ([]models.InterestRisk, error) {
	var results []models.InterestRisk
	for _, line := range splitLines(raw) {
		parts := strings.Split(line, "\t")
		if len(parts) != 4 {
			continue
		}
		total, err1 := strconv.Atoi(strings.TrimSpace(parts[1]))
		avgRate, err2 := strconv.ParseFloat(strings.TrimSpace(parts[2]), 64)
		defaultRate, err3 := strconv.ParseFloat(strings.TrimSpace(parts[3]), 64)
		if err1 != nil || err2 != nil || err3 != nil {
			return nil, fmt.Errorf("interest parse error on line %q: %v %v %v", line, err1, err2, err3)
		}
		grade := strings.TrimSpace(parts[0])
		results = append(results, models.InterestRisk{
			Grade:           grade,
			TotalLoans:      total,
			AvgInterestRate: avgRate,
			DefaultRate:     defaultRate,
			RiskLevel:       models.ClassifyRisk(defaultRate),
		})
	}
	return results, nil
}

// splitLines breaks a raw string into non-empty trimmed lines.
func splitLines(raw string) []string {
	var out []string
	for _, line := range strings.Split(raw, "\n") {
		line = strings.TrimSpace(line)
		if line != "" {
			out = append(out, line)
		}
	}
	return out
}
