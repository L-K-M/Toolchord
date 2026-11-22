function makeSeed(options, api) {
    return api.now === null ? "" : String(api.now);
}

function offsetSuffix(offset) {
    const magnitude = Math.abs(offset);
    const pad = n => String(n).padStart(2, "0");
    const seconds = magnitude % 60;
    return (offset < 0 ? "-" : "+") + pad(Math.floor(magnitude / 3600)) + ":" +
        pad(Math.floor(magnitude / 60) % 60) + (seconds ? ":" + pad(seconds) : "");
}

function relativeTime(ms, now) {
    const delta = Math.abs(ms - Math.floor(now));
    const units = [[31536000000, "year"], [2592000000, "month"], [86400000, "day"],
                   [3600000, "hour"], [60000, "minute"], [1000, "second"]];
    for (const [size, unit] of units) {
        if (delta < size) continue;
        const count = Math.floor(delta / size);
        const value = count + " " + unit + (count === 1 ? "" : "s");
        return ms > now ? "in " + value : value + " ago";
    }
    return "now";
}

function preview(input, options, api) {
    const fromUnix = api.id === "time.fromUnix", captured = api.id === "time.now";
    const unit = options.unit || "auto";
    const parsed = captured ? parseClockInput("seed", api.seed, unit, api) :
        parseClockInput(fromUnix ? "unix" : "rfc3339", input, unit, api);
    if (parsed && parsed.error) return parsed;
    const ms = fromUnix ? parsed.milliseconds : parsed;
    const utc = new Date(ms).toISOString();
    const offset = api.native("clock.offsetSeconds", ms);
    const local = new Date(ms + offset * 1000).toISOString()
        .replace(/^\+(0*)(\d{5,})-/, "$2-").replace(/Z$/, offsetSuffix(offset));
    const seconds = String(ms / 1000);
    const field = (id, label, value) => ({id, label, value});
    const secondsField = field("seconds", "Unix seconds", seconds);
    const millisField = field("milliseconds", "Unix milliseconds", String(ms));
    const utcField = field("utc", "UTC", utc);
    const localField = {...field("local", "Local", local), note: api.timeZone};
    if (fromUnix) {
        const relative = {...field("relative", "Relative", relativeTime(ms, api.now)), isCopyable: false, isMonospaced: false};
        return {primaryText: utc, status: parsed.unit === "ms" ? "Read as milliseconds" : "Read as seconds",
                fields: [utcField, localField, secondsField, millisField, relative]};
    }
    const primary = captured
        ? ({ms: String(ms), iso: utc, s: String(Math.floor(ms / 1000))})[options.format]
        : (unit === "ms" ? String(ms) : seconds);
    return {primaryText: primary, status: captured ? "Captured at " + local.split("T")[1].slice(0, 8) : "UTC " + utc,
            fields: [secondsField, millisField, utcField, localField]};
}
