export function parsePositiveInteger(value: string | null): number | null {
  if (!value || !/^\d+$/.test(value)) return null;
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : null;
}

export function isFreshQrTimestamp(timestamp: unknown, now = Date.now()): boolean {
  return typeof timestamp === 'number' && Number.isFinite(timestamp) &&
    now - timestamp <= 30_000 && now - timestamp >= -5_000;
}

export function isValidAttendanceDay(day: number, numberOfDays: number): boolean {
  return Number.isSafeInteger(day) && Number.isSafeInteger(numberOfDays) &&
    day >= 1 && day <= numberOfDays;
}
