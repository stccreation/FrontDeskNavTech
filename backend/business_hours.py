from collections import defaultdict
from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta
from zoneinfo import ZoneInfo


BUSINESS_ZONE = ZoneInfo("Asia/Kolkata")
OPENS = time(9, 30)
CLOSES = time(18, 30)
DAY = timedelta(days=1)


def local_date(timestamp):
    return timestamp.replace(tzinfo=UTC).astimezone(BUSINESS_ZONE).date()


def utc_boundary(day, clock_time):
    return datetime.combine(day, clock_time, BUSINESS_ZONE).astimezone(UTC).replace(tzinfo=None)


@dataclass(frozen=True)
class HolidayEvent:
    day: date
    name: str
    active: bool
    effective_at: datetime


class BusinessCalendar:
    def __init__(self, events=()):
        self.events = tuple(events)
        self.by_day = defaultdict(list)
        for event in self.events:
            self.by_day[event.day].append(event)

    def active_holidays(self):
        return {day: events[-1].name for day, events in self.by_day.items() if events[-1].active}

    def intervals(self, day):
        if day.weekday() >= 5:
            return
        start, end = utc_boundary(day, OPENS), utc_boundary(day, CLOSES)
        working = True
        for event in self.by_day.get(day, ()):
            if event.effective_at >= end:
                break
            if event.effective_at > start:
                if working:
                    yield start, event.effective_at
                start = event.effective_at
            working = not event.active
        if working and start < end:
            yield start, end

    def add_working_time(self, start, duration):
        if duration <= timedelta(0):
            return start
        day = local_date(start)
        while True:
            for opens, closes in self.intervals(day):
                begins = max(start, opens)
                if begins < closes:
                    available = closes - begins
                    if duration <= available:
                        return begins + duration
                    duration -= available
            day += DAY

    def working_time_between(self, start, end):
        total = timedelta(0)
        day, last_day = local_date(start), local_date(end)
        while day <= last_day:
            for opens, closes in self.intervals(day):
                total += max(timedelta(0), min(end, closes) - max(start, opens))
            day += DAY
        return total

    def working_day_close(self, start):
        day = local_date(start)
        while True:
            remaining = [closes for _, closes in self.intervals(day) if closes > start]
            if remaining:
                return remaining[-1]
            day += DAY
