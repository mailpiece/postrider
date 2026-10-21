import { Controller } from "@hotwired/stimulus"
import { differenceInDays, secondsToDate } from "helpers/date_helpers"

export default class extends Controller {
  static targets = [ "time", "date", "datetime", "shortdate", "ago", "indays", "daysago", "agoorweekday", "timeordate" ]
  static values = { refreshInterval: Number }
  static classes = [ "local-time-value"]

  #timer

  initialize() {
    this.#buildFormatters()
  }

  connect() {
    this.#timer = setInterval(() => this.#refreshRelativeTimes(), 30_000)
  }

  disconnect() {
    clearInterval(this.#timer)
  }

  refreshAll() {
    this.#buildFormatters()

    this.constructor.targets.forEach(targetName => {
      this.targets.findAll(targetName).forEach(target => {
        this.#formatTime(this[`${targetName}Formatter`], target)
      })
    })
  }

  refreshTarget(event) {
    const target = event.target;
    const targetName = target.dataset.readerTimeTarget
    this.#formatTime(this[`${targetName}Formatter`], target)
  }

  timeTargetConnected(target) {
    this.#formatTime(this.timeFormatter, target)
  }

  dateTargetConnected(target) {
    this.#formatTime(this.dateFormatter, target)
  }

  datetimeTargetConnected(target) {
    this.#formatTime(this.datetimeFormatter, target)
  }

  shortdateTargetConnected(target) {
    this.#formatTime(this.shortdateFormatter, target)
  }

  agoTargetConnected(target) {
    this.#formatTime(this.agoFormatter, target)
  }

  indaysTargetConnected(target) {
    this.#formatTime(this.indaysFormatter, target)
  }

  daysagoTargetConnected(target) {
    this.#formatTime(this.daysagoFormatter, target)
  }

  agoorweekdayTargetConnected(target) {
    this.#formatTime(this.agoorweekdayFormatter, target)
  }

  timeordateTargetConnected(target) {
    this.#formatTime(this.timeordateFormatter, target)
  }

  // Morphing a page into another language keeps this controller, so the locale is read again on refresh.
  #buildFormatters() {
    const locale = document.documentElement.lang || undefined

    this.timeFormatter = new Intl.DateTimeFormat(locale, { timeStyle: "short" })
    this.dateFormatter = new Intl.DateTimeFormat(locale, { dateStyle: "long" })
    this.shortdateFormatter = new Intl.DateTimeFormat(locale, { month: "short", day: "numeric" })
    this.datetimeFormatter = new Intl.DateTimeFormat(locale, { timeStyle: "short", dateStyle: "short" })
    this.agoFormatter = new AgoFormatter(locale)
    this.daysagoFormatter = new DaysAgoFormatter(locale)
    this.datewithweekdayFormatter = new Intl.DateTimeFormat(locale, { weekday: "long", month: "long", day: "numeric" })
    this.datewithweekdayFormatter = new Intl.DateTimeFormat(locale, { weekday: "long", month: "long", day: "numeric" })
    this.indaysFormatter = new InDaysFormatter(locale)
    this.agoorweekdayFormatter = new DaysAgoOrWeekdayFormatter(locale)
    this.timeordateFormatter = new TimeOrDateFormatter(locale)
  }

  #refreshRelativeTimes() {
    this.agoTargets.forEach(target => {
      this.#formatTime(this.agoFormatter, target)
    })

    this.agoorweekdayTargets.forEach(target => {
      this.#formatTime(this.agoorweekdayFormatter, target)
    })
  }

  #formatTime(formatter, target) {
    const dt = secondsToDate(parseInt(target.getAttribute("datetime")))
    target.innerHTML = formatter.format(dt)
    target.title = this.datetimeFormatter.format(dt)
  }
}

class AgoFormatter {
  constructor(locale) {
    this.numeric = new Intl.RelativeTimeFormat(locale, { numeric: "always" })
    this.words = new Intl.RelativeTimeFormat(locale, { numeric: "auto" })
  }

  format(dt) {
    const now = new Date()
    const seconds = (now - dt) / 1000
    const minutes = seconds / 60
    const hours = minutes / 60
    const days = hours / 24
    const weeks = days / 7
    const months = days / (365 / 12)
    const years = days / 365

    if (years >= 1) return this.#ago(years, "year")
    if (months >= 1) return this.#ago(months, "month")
    if (weeks >= 1) return this.#ago(weeks, "week")
    if (days >= 1) return this.#ago(days, "day")
    if (hours >= 1) return this.#ago(hours, "hour")
    if (minutes >= 1) return this.#ago(minutes, "minute")

    return this.words.format(0, "second")
  }

  #ago(quantity, unit) {
    return this.numeric.format(-Math.floor(quantity), unit)
  }
}

// "auto" words only today and the day beside it: at two days it would say "anteayer" where English says "2 days ago".
class DaysAgoFormatter {
  constructor(locale) {
    this.numeric = new Intl.RelativeTimeFormat(locale, { numeric: "always" })
    this.words = new Intl.RelativeTimeFormat(locale, { numeric: "auto" })
  }

  format(date) {
    const days = differenceInDays(date, new Date())

    if (days <= 0) return styleableRelativeTime(this.words, 0)
    if (days === 1) return styleableRelativeTime(this.words, -1)
    return styleableRelativeTime(this.numeric, -days)
  }
}

class DaysAgoOrWeekdayFormatter {
  constructor(locale) {
    this.daysago = new DaysAgoFormatter(locale)
    this.weekday = new Intl.DateTimeFormat(locale, { weekday: "long", month: "long", day: "numeric" })
    this.weekdayWithYear = new Intl.DateTimeFormat(locale, { weekday: "long", month: "long", day: "numeric", year: "numeric" })
  }

  format(date) {
    const today = new Date()
    const days = differenceInDays(date, today)

    if (days <= 1) {
      return this.daysago.format(date)
    } else if (date.getFullYear() === today.getFullYear()) {
      return this.weekday.format(date)
    } else {
      return this.weekdayWithYear.format(date)
    }
  }
}

class InDaysFormatter {
  constructor(locale) {
    this.numeric = new Intl.RelativeTimeFormat(locale, { numeric: "always" })
    this.words = new Intl.RelativeTimeFormat(locale, { numeric: "auto" })
  }

  format(date) {
    const days = differenceInDays(new Date(), date)

    if (days <= 0) return styleableRelativeTime(this.words, 0)
    if (days === 1) return styleableRelativeTime(this.words, 1)
    return styleableRelativeTime(this.numeric, days)
  }
}

class TimeOrDateFormatter {
  constructor(locale) {
    this.date = new Intl.DateTimeFormat(locale, { month: "short", day: "numeric" })
    this.time = new Intl.DateTimeFormat(locale, { timeStyle: "short" })
  }

  format(date) {
    const days = differenceInDays(date, new Date())

    if (days >= 1) {
      return this.date.format(date)
    } else {
      return this.time.format(date)
    }
  }
}

// A worded day ("yesterday", "ayer") is styled whole; a counted one only in its number.
function styleableRelativeTime(formatter, days) {
  const parts = formatter.formatToParts(days, "day")
  const first = parts.findIndex(part => part.type !== "literal")

  if (first === -1) {
    return styleableValue(joinParts(parts))
  } else {
    const last = parts.findLastIndex(part => part.type !== "literal")
    return joinParts(parts.slice(0, first)) + styleableValue(joinParts(parts.slice(first, last + 1))) + joinParts(parts.slice(last + 1))
  }
}

function joinParts(parts) {
  return parts.map(part => part.value).join("")
}

function styleableValue(value) {
  return `<span class="local-time-value">${value}</span>`
}
