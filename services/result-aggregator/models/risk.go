// Package models defines the core risk analysis data structures shared across
// the result aggregator and API gateway.
package models

// RiskLevel represents the categorical risk tier derived from default rate thresholds.
type RiskLevel string

const (
	RiskLow      RiskLevel = "LOW"
	RiskMedium   RiskLevel = "MEDIUM"
	RiskHigh     RiskLevel = "HIGH"
	RiskCritical RiskLevel = "CRITICAL"
)

// ClassifyRisk maps a default rate percentage to a RiskLevel.
// Thresholds: <5% LOW, 5-15% MEDIUM, 15-25% HIGH, >25% CRITICAL.
func ClassifyRisk(defaultRatePct float64) RiskLevel {
	switch {
	case defaultRatePct < 5.0:
		return RiskLow
	case defaultRatePct < 15.0:
		return RiskMedium
	case defaultRatePct < 25.0:
		return RiskHigh
	default:
		return RiskCritical
	}
}

// LoanGradeRisk holds default statistics for a single loan grade (A–G).
type LoanGradeRisk struct {
	Grade       string    `json:"grade"`
	TotalLoans  int       `json:"total_loans"`
	Defaults    int       `json:"total_defaults"`
	DefaultRate float64   `json:"default_rate_pct"`
	RiskLevel   RiskLevel `json:"risk_level"`
}

// StateRisk holds default statistics for a single US state.
type StateRisk struct {
	State       string    `json:"state"`
	TotalLoans  int       `json:"total_loans"`
	Defaults    int       `json:"total_defaults"`
	DefaultRate float64   `json:"default_rate_pct"`
	RiskLevel   RiskLevel `json:"risk_level"`
}

// EmploymentRisk holds default statistics for an employment-length bucket.
type EmploymentRisk struct {
	Bucket      string    `json:"employment_bucket"`
	TotalLoans  int       `json:"total_loans"`
	Defaults    int       `json:"total_defaults"`
	DefaultRate float64   `json:"default_rate_pct"`
	RiskLevel   RiskLevel `json:"risk_level"`
}

// InterestRisk surfaces the risk-return tradeoff per loan grade.
type InterestRisk struct {
	Grade           string    `json:"grade"`
	TotalLoans      int       `json:"total_loans"`
	AvgInterestRate float64   `json:"avg_interest_rate"`
	DefaultRate     float64   `json:"default_rate_pct"`
	RiskLevel       RiskLevel `json:"risk_level"`
}

// RiskSummary is the aggregated cross-job risk report.
type RiskSummary struct {
	HighestRiskGrade     string  `json:"highest_risk_grade"`
	HighestRiskState     string  `json:"highest_risk_state"`
	HighestRiskEmpBucket string  `json:"highest_risk_employment_bucket"`
	LowestRiskGrade      string  `json:"lowest_risk_grade"`
	OverallDefaultRate   float64 `json:"overall_default_rate_pct"`
	TotalLoansAnalyzed   int     `json:"total_loans_analyzed"`
	Recommendation       string  `json:"recommendation"`
}
