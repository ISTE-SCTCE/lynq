# Implementation Plan: Budget Dashboard Enhancements

This plan outlines the steps to integrate a financial trend graph into the budget dashboard, fix the data synchronization in PDF reports, and populate the income/expense ledger tabs.

## Proposed Changes

### Budget Overview Screen
`lib/screens/budget/budget_overview_screen.dart`

#### [MODIFY] [budget_overview_screen.dart](file:///c:/Users/yuuge/OneDrive/Desktop/admin/execcom_app/lib/screens/budget/budget_overview_screen.dart)

- **State Management**:
    - Add `List<Map<String, dynamic>> _ledgerEntries = []` to track individual transactions.
    - Update `_loadBudget()` to store the fetched ledger data.
- **Navigation & UI**:
    - Remove "Income" and "Expense" tabs from the `TabBar` and `TabBarView`.
    - Adjust `TabController` length accordingly.
- **Dashboard Tab**:
    - Replace the "Recent Trends" placeholder with an `fl_chart` implementation (Bar or Line chart).
    - Display aggregated Income (Green) and Expense (Red) trends.
    - Add a "Recent Transactions" section at the bottom of the Dashboard or within the "History" tab that includes `financial_ledger` entries.
- **PDF Generation**:
    - Fix logic in `_downloadPdfReport()`:
        - Use `_totalIncome` and `_totalSpent` for the statement header.
        - Update the transaction history table to list actual ledger entries from `financial_ledger`.

## Verification Plan

### Automated Tests
- No automated tests required for this UI-heavy change, but I will verify the logic via code review.

### Manual Verification
1.  **Dashboard**: Verify that the new graph appears and accurately represents the income/expense ratio.
2.  **Ledger Tabs**: Verify that clicking "Income" or "Expense" tabs shows the correct transaction lists.
3.  **PDF Export**: Generate a report and confirm that the "Total Income" and "Total Expense" match those on the dashboard, and that the transaction table contains ledger entries.
4.  **Data Consistency**: Add a new income/expense via the dashboard and ensure the graph and tabs update instantly.
