import unittest
from datetime import date, time, timedelta

from business_hours import BusinessCalendar, HolidayEvent, utc_boundary
from sla import proposed_deadlines


def ist(day, hour, minute=0):
    return utc_boundary(date.fromisoformat(day), time(hour, minute))


class BusinessHoursTest(unittest.TestCase):
    def test_friday_evening_uses_only_working_time(self):
        start = ist("2026-11-20", 18)
        calendar = BusinessCalendar()
        deadlines = proposed_deadlines(calendar, "urgent", start)
        self.assertEqual(deadlines["first_response"][0], ist("2026-11-23", 11))
        self.assertEqual(deadlines["resolution"][0], ist("2026-11-20", 18, 30))
        self.assertEqual(calendar.working_time_between(start, ist("2026-11-22", 10)), timedelta(minutes=30))

    def test_eod_at_closing_moves_to_next_available_working_day(self):
        friday_close = ist("2026-11-20", 18, 30)
        holiday = HolidayEvent(date(2026, 11, 23), "Festival", True, friday_close)
        self.assertEqual(BusinessCalendar([holiday]).working_day_close(friday_close), ist("2026-11-24", 18, 30))

    def test_before_opening_uses_same_day_close(self):
        self.assertEqual(BusinessCalendar().working_day_close(ist("2026-11-24", 7)), ist("2026-11-24", 18, 30))

    def test_today_edits_leave_earlier_work_intact(self):
        day = date(2026, 11, 24)
        calendar = BusinessCalendar([
            HolidayEvent(day, "Festival", True, ist("2026-11-24", 12)),
            HolidayEvent(day, "Festival", False, ist("2026-11-24", 15, 30)),
        ])
        start = ist("2026-11-24", 9, 30)
        self.assertEqual(calendar.working_time_between(start, ist("2026-11-24", 18, 30)), timedelta(hours=5.5))
        self.assertEqual(calendar.add_working_time(start, timedelta(hours=4.5)), ist("2026-11-24", 17, 30))

    def test_medium_and_low_deadlines(self):
        calendar = BusinessCalendar()
        start = ist("2026-11-24", 10)
        medium = proposed_deadlines(calendar, "medium", start)
        self.assertEqual(medium["first_response"][0], ist("2026-11-24", 14, 30))
        self.assertEqual(medium["resolution"][0], ist("2026-11-27", 10))
        low = proposed_deadlines(calendar, "low", start)
        self.assertEqual(low["first_response"][0], ist("2026-11-25", 10))
        self.assertEqual(low["resolution"][0], ist("2026-12-01", 10))

    def test_finishing_exactly_at_close_stays_on_that_day(self):
        calendar = BusinessCalendar()
        start = ist("2026-11-27", 14)
        self.assertEqual(calendar.add_working_time(start, timedelta(hours=4.5)), ist("2026-11-27", 18, 30))


if __name__ == "__main__":
    unittest.main()
