"""Scheduler entrypoint for the recurring jobs (§10).

Run with: ``python -m app.jobs.worker``

Schedules are in server-local time here for simplicity; the spec calls for
per-user-local-time triggers (06:00/07:00), which a production deployment would
implement by enqueueing per-user jobs from a timezone-aware planner.
"""
from __future__ import annotations

import asyncio
import logging

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger

from . import tasks

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("northax.worker")


def build_scheduler() -> AsyncIOScheduler:
    scheduler = AsyncIOScheduler(timezone="UTC")
    # garmin-sync — daily 06:00
    scheduler.add_job(tasks.refresh_garmin_tokens, CronTrigger(minute=0), id="refresh-garmin-token")
    # compute-readiness — daily 07:00
    scheduler.add_job(tasks.compute_readiness_all, CronTrigger(hour=7, minute=0), id="compute-readiness")
    # prune-coach-history — weekly, Monday 04:00
    scheduler.add_job(
        tasks.prune_coach_history, CronTrigger(day_of_week="mon", hour=4, minute=0), id="prune-coach-history"
    )
    return scheduler


async def main() -> None:
    scheduler = build_scheduler()
    scheduler.start()
    log.info("NorthAx worker started; jobs scheduled.")
    try:
        await asyncio.Event().wait()  # run forever
    except (KeyboardInterrupt, SystemExit):
        scheduler.shutdown()


if __name__ == "__main__":
    asyncio.run(main())
