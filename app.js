(() => {
  'use strict';

  const WEATHER_API = 'https://api.open-meteo.com/v1/forecast';
  const AIR_QUALITY_API = 'https://air-quality-api.open-meteo.com/v1/air-quality';
  const GEOCODING_API = 'https://geocoding-api.open-meteo.com/v1/search';
  const PLACE_KEY = 'omarchy-weather:place';
  const UNIT_KEY = 'omarchy-weather:unit';
  const CACHE_PREFIX = 'omarchy-weather:forecast:';
  const AIR_CACHE_PREFIX = 'omarchy-weather:air-quality:';
  const DEFAULT_PLACE = {
    id: 'islamabad-pk',
    name: 'Islamabad',
    admin1: 'Islamabad Capital Territory',
    country: 'Pakistan',
    latitude: 33.6844,
    longitude: 73.0479,
    timezone: 'Asia/Karachi',
  };

  const $ = (selector) => document.querySelector(selector);
  const elements = {
    searchForm: $('#search-form'),
    searchInput: $('#place-search'),
    searchResults: $('#search-results'),
    locationName: $('#location-name'),
    locationContext: $('#location-context'),
    localClock: $('#local-clock'),
    localDate: $('#local-date'),
    dataStatus: $('#data-status'),
    statusText: $('#status-text'),
    refreshButton: $('#refresh-button'),
    locateButton: $('#locate-button'),
    installButton: $('#install-button'),
    weatherAlert: $('#weather-alert'),
    weatherAlertText: $('#weather-alert-text'),
    retryButton: $('#retry-button'),
    currentTemperature: $('#current-temperature'),
    currentUnit: $('#current-unit'),
    currentCondition: $('#current-condition'),
    temperatureAccessibleLabel: $('#temperature-accessible-label'),
    feelsLikeTemperature: $('#feels-like-temperature'),
    heroWeatherIcon: $('#hero-weather-icon'),
    todayHigh: $('#today-high'),
    todayLow: $('#today-low'),
    sunTimes: $('#sun-times'),
    humidityValue: $('#humidity-value'),
    humidityNote: $('#humidity-note'),
    windValue: $('#wind-value'),
    windNote: $('#wind-note'),
    rainValue: $('#rain-value'),
    rainNote: $('#rain-note'),
    uvValue: $('#uv-value'),
    uvNote: $('#uv-note'),
    hourlyForecast: $('#hourly-forecast'),
    dailyForecast: $('#daily-forecast'),
    airQualityPanel: $('#air-quality-panel'),
    airQualityUpdated: $('#air-quality-updated'),
    usAqi: $('#us-aqi'),
    airCategory: $('#air-category'),
    airAdvice: $('#air-advice'),
    aqiMarker: $('#aqi-marker'),
    pm25Value: $('#pm25-value'),
    pm10Value: $('#pm10-value'),
    ozoneValue: $('#ozone-value'),
    nitrogenDioxideValue: $('#nitrogen-dioxide-value'),
    toast: $('#app-toast'),
    toastMessage: $('#toast-message'),
    toastClose: $('#toast-close'),
  };

  function readStoredValue(key) {
    try {
      return window.localStorage.getItem(key);
    } catch {
      return null;
    }
  }

  function readStoredJson(key) {
    const value = readStoredValue(key);
    if (!value) return null;
    try {
      return JSON.parse(value);
    } catch {
      return null;
    }
  }

  function writeStoredJson(key, value) {
    try {
      window.localStorage.setItem(key, JSON.stringify(value));
    } catch {
      // Weather still works when browser storage is blocked or full.
    }
  }

  function isValidPlace(place) {
    return Boolean(
      place &&
      typeof place.name === 'string' &&
      Number.isFinite(Number(place.latitude)) &&
      Number.isFinite(Number(place.longitude)),
    );
  }

  const storedPlace = readStoredJson(PLACE_KEY);
  const storedUnit = readStoredValue(UNIT_KEY);
  const state = {
    place: isValidPlace(storedPlace) ? storedPlace : DEFAULT_PLACE,
    unit: storedUnit === 'f' ? 'f' : 'c',
    weather: null,
    airQuality: null,
    isLoading: false,
    isAirLoading: false,
    status: { tone: 'loading', label: 'Connecting' },
    airStatus: { tone: 'loading', label: 'Checking air' },
    searchResults: [],
    activeSearchIndex: -1,
    searchTimer: null,
    searchController: null,
    weatherController: null,
    weatherRequestId: 0,
    airQualityController: null,
    airQualityRequestId: 0,
    toastTimer: null,
    installPrompt: null,
  };

  const WEATHER_ART = {
    sunny: `
      <circle cx="49" cy="46" r="15" />
      <path d="M49 12v9m0 50v9M15 46h9m50 0h9M25 22l6 6m36 36 6 6m0-48-6 6M31 64l-6 6" />
    `,
    night: `
      <path d="M62 18a29 29 0 1 0 20 47.6A31 31 0 0 1 62 18Z" />
      <path d="m73 22 1.5 3.5L78 27l-3.5 1.5L73 32l-1.5-3.5L68 27l3.5-1.5L73 22ZM39 18l1.2 2.8L43 22l-2.8 1.2L39 26l-1.2-2.8L35 22l2.8-1.2L39 18Z" />
    `,
    partly: `
      <circle cx="63" cy="32" r="12" />
      <path d="M63 10v5m0 34v5M41 32h5m34 0h5M47.5 16.5l3.5 3.5m24 24 3.5 3.5m0-31-3.5 3.5M51 44l-3.5 3.5" />
      <path d="M25 70h48a13 13 0 0 0 0-26 17 17 0 0 0-32.5 3.8A11.5 11.5 0 0 0 25 70Z" />
    `,
    cloudy: `
      <path d="M25 69h48a13 13 0 0 0 0-26 17 17 0 0 0-32.5 3.8A11.5 11.5 0 0 0 25 69Z" />
    `,
    fog: `
      <path d="M27 58h42a11 11 0 0 0 0-22 15 15 0 0 0-28.8 3.4A10 10 0 0 0 27 58Z" />
      <path d="M20 68h48M29 77h43" />
    `,
    drizzle: `
      <path d="M24 61h48a12 12 0 0 0 0-24 16 16 0 0 0-30.6 3.6A11 11 0 0 0 24 61Z" />
      <path d="m37 70-2 5m17-5-2 5m17-5-2 5" />
    `,
    rain: `
      <path d="M24 57h48a12 12 0 0 0 0-24 16 16 0 0 0-30.6 3.6A11 11 0 0 0 24 57Z" />
      <path d="m36 66-4 9m19-9-4 9m19-9-4 9" />
    `,
    snow: `
      <path d="M24 55h48a12 12 0 0 0 0-24 16 16 0 0 0-30.6 3.6A11 11 0 0 0 24 55Z" />
      <path d="M37 65v14m-5-11 10 8m0-8-10 8m23-11v14m-5-11 10 8m0-8-10 8" />
    `,
    storm: `
      <path d="M23 56h50a12 12 0 0 0 0-24 16 16 0 0 0-31 3.6A11 11 0 0 0 23 56Z" />
      <path d="m51 58-9 15h9l-3 12 15-19h-10l5-8" />
    `,
  };

  function weatherIcon(kind) {
    const art = WEATHER_ART[kind] || WEATHER_ART.cloudy;
    return `<svg class="weather-icon ${kind}" viewBox="0 0 100 100" fill="none" focusable="false" aria-hidden="true">${art}</svg>`;
  }

  function weatherInfo(code, isDay = true) {
    const numericCode = Number(code);
    if (numericCode === 0) {
      return { label: isDay ? 'Clear sky' : 'Clear night', icon: isDay ? 'sunny' : 'night' };
    }
    if (numericCode === 1) return { label: 'Mainly clear', icon: 'partly' };
    if (numericCode === 2) return { label: 'Partly cloudy', icon: 'partly' };
    if (numericCode === 3) return { label: 'Overcast', icon: 'cloudy' };
    if (numericCode === 45 || numericCode === 48) return { label: 'Fog', icon: 'fog' };
    if ([51, 53, 55, 56, 57].includes(numericCode)) return { label: 'Drizzle', icon: 'drizzle' };
    if ([61, 63, 65, 66, 67, 80, 81, 82].includes(numericCode)) {
      return { label: numericCode >= 80 && numericCode <= 82 ? 'Rain showers' : 'Rain', icon: 'rain' };
    }
    if ([71, 73, 75, 77, 85, 86].includes(numericCode)) {
      return { label: numericCode >= 85 ? 'Snow showers' : 'Snow', icon: 'snow' };
    }
    if ([95, 96, 99].includes(numericCode)) return { label: 'Thunderstorm', icon: 'storm' };
    return { label: 'Mixed conditions', icon: 'cloudy' };
  }

  function safeNumber(value) {
    if (value === null || value === undefined || value === '') return null;
    const number = Number(value);
    return Number.isFinite(number) ? number : null;
  }

  function temperatureValue(celsius) {
    const value = safeNumber(celsius);
    if (value === null) return null;
    return state.unit === 'f' ? value * 9 / 5 + 32 : value;
  }

  function formatTemperature(value) {
    const converted = temperatureValue(value);
    return converted === null ? '—' : `${Math.round(converted)}°`;
  }

  function formatTemperatureAccessible(value) {
    const converted = temperatureValue(value);
    if (converted === null) return 'Temperature unavailable';
    const unitName = state.unit === 'f' ? 'Fahrenheit' : 'Celsius';
    return `${Math.round(converted)} degrees ${unitName}`;
  }

  function formatDecimal(value) {
    const number = safeNumber(value);
    return number === null ? '—' : number.toFixed(1).replace(/\.0$/, '');
  }

  function formatWindSpeed(kilometersPerHour) {
    const value = safeNumber(kilometersPerHour);
    if (value === null) return '—';
    const converted = state.unit === 'f' ? value * 0.621371 : value;
    return `${Math.round(converted)} ${state.unit === 'f' ? 'mph' : 'km/h'}`;
  }

  function compassDirection(degrees) {
    const value = safeNumber(degrees);
    if (value === null) return '';
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    return directions[Math.round(value / 45) % directions.length];
  }

  function parseWallTime(value) {
    if (typeof value !== 'string' || !value) return null;
    let normalized = value;
    if (/^\d{4}-\d{2}-\d{2}$/.test(normalized)) {
      normalized += 'T12:00:00Z';
    } else if (!/(?:Z|[+-]\d{2}:?\d{2})$/i.test(normalized)) {
      if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(normalized)) normalized += ':00';
      normalized += 'Z';
    }
    const date = new Date(normalized);
    return Number.isNaN(date.getTime()) ? null : date;
  }

  function formatForecastTime(value) {
    const date = parseWallTime(value);
    if (!date) return '—';
    return new Intl.DateTimeFormat(undefined, {
      hour: 'numeric',
      timeZone: 'UTC',
    }).format(date);
  }

  function formatForecastWeekday(value) {
    const date = parseWallTime(value);
    if (!date) return '—';
    return new Intl.DateTimeFormat(undefined, {
      weekday: 'short',
      timeZone: 'UTC',
    }).format(date);
  }

  function formatForecastDate(value) {
    const date = parseWallTime(value);
    if (!date) return '';
    return new Intl.DateTimeFormat(undefined, {
      month: 'short',
      day: 'numeric',
      timeZone: 'UTC',
    }).format(date);
  }

  function updateLocalClock() {
    const timeZone = state.weather?.timezone || state.place.timezone || undefined;
    const now = new Date();
    try {
      elements.localClock.textContent = new Intl.DateTimeFormat(undefined, {
        hour: 'numeric',
        minute: '2-digit',
        timeZone,
        timeZoneName: 'short',
      }).format(now);
      elements.localDate.textContent = new Intl.DateTimeFormat(undefined, {
        weekday: 'long',
        month: 'long',
        day: 'numeric',
        timeZone,
      }).format(now);
    } catch {
      elements.localClock.textContent = new Intl.DateTimeFormat(undefined, {
        hour: 'numeric',
        minute: '2-digit',
      }).format(now);
      elements.localDate.textContent = new Intl.DateTimeFormat(undefined, {
        weekday: 'long',
        month: 'long',
        day: 'numeric',
      }).format(now);
    }
  }

  function locationDescription(place) {
    if (place.name === 'My location') {
      const latitude = Math.abs(Number(place.latitude)).toFixed(2);
      const longitude = Math.abs(Number(place.longitude)).toFixed(2);
      const northSouth = Number(place.latitude) >= 0 ? 'N' : 'S';
      const eastWest = Number(place.longitude) >= 0 ? 'E' : 'W';
      return `${latitude}° ${northSouth}, ${longitude}° ${eastWest}`;
    }
    const parts = [place.admin1, place.country]
      .filter((part, index, values) => part && values.indexOf(part) === index && part !== place.name);
    return parts.join(' · ') || (place.country || 'Weather location');
  }

  function forecastCacheKey(place) {
    return `${CACHE_PREFIX}${Number(place.latitude).toFixed(3)},${Number(place.longitude).toFixed(3)}`;
  }

  function readForecastCache(place) {
    const cached = readStoredJson(forecastCacheKey(place));
    if (!cached || !cached.weather?.current || !cached.weather?.daily || !cached.weather?.hourly) return null;
    return cached;
  }

  function airQualityCacheKey(place) {
    return `${AIR_CACHE_PREFIX}${Number(place.latitude).toFixed(3)},${Number(place.longitude).toFixed(3)}`;
  }

  function readAirQualityCache(place) {
    const cached = readStoredJson(airQualityCacheKey(place));
    if (!cached || !cached.airQuality?.current) return null;
    return cached;
  }

  function setStatus(tone, label) {
    state.status = { tone, label };
    elements.dataStatus.className = `status-pill is-${tone}`;
    elements.statusText.textContent = label;
    elements.refreshButton.classList.toggle('is-refreshing', state.isLoading);
    elements.refreshButton.disabled = state.isLoading;
    elements.locateButton.disabled = state.isLocating === true;
  }

  function setText(element, value) {
    element.textContent = value;
  }

  function updateUnitButtons() {
    document.querySelectorAll('[data-unit]').forEach((button) => {
      const active = button.dataset.unit === state.unit;
      button.setAttribute('aria-pressed', String(active));
    });
    setText(elements.currentUnit, state.unit.toUpperCase());
  }

  function renderLocation() {
    setText(elements.locationName, state.place.name);
    setText(elements.locationContext, locationDescription(state.place));
    updateLocalClock();
  }

  function showForecastPlaceholder(message) {
    elements.hourlyForecast.innerHTML = `<p class="loading-note">${message}</p>`;
    elements.dailyForecast.innerHTML = `<p class="loading-note">${message}</p>`;
  }

  function nearestHourIndex(weather) {
    const hourlyTimes = weather.hourly?.time || [];
    if (!hourlyTimes.length) return -1;
    const currentHour = String(weather.current?.time || '').slice(0, 13);
    const index = hourlyTimes.findIndex((time) => String(time).slice(0, 13) >= currentHour);
    return index < 0 ? 0 : index;
  }

  function renderCurrent(weather) {
    const current = weather.current || {};
    const daily = weather.daily || {};
    const todayIndex = Math.max(0, (daily.time || []).indexOf(String(current.time || '').slice(0, 10)));
    const isDay = Number(current.is_day) !== 0;
    const info = weatherInfo(current.weather_code, isDay);
    const temperature = current.temperature_2m;
    const feelsLike = current.apparent_temperature;

    setText(elements.currentTemperature, temperatureValue(temperature) === null ? '—' : String(Math.round(temperatureValue(temperature))));
    setText(elements.currentUnit, state.unit.toUpperCase());
    setText(elements.currentCondition, info.label);
    setText(elements.feelsLikeTemperature, formatTemperature(feelsLike));
    elements.temperatureAccessibleLabel.setAttribute('aria-label', `Current temperature: ${formatTemperatureAccessible(temperature)}`);
    elements.heroWeatherIcon.innerHTML = weatherIcon(info.icon);

    const high = daily.temperature_2m_max?.[todayIndex];
    const low = daily.temperature_2m_min?.[todayIndex];
    setText(elements.todayHigh, formatTemperature(high));
    setText(elements.todayLow, formatTemperature(low));

    const sunrise = daily.sunrise?.[todayIndex];
    const sunset = daily.sunset?.[todayIndex];
    setText(
      elements.sunTimes,
      `Sunrise ${formatForecastTime(sunrise)} · Sunset ${formatForecastTime(sunset)}`,
    );

    renderMetrics(weather, todayIndex);
  }

  function uvDescription(value) {
    const index = safeNumber(value);
    if (index === null) return 'Peak today';
    if (index <= 2) return 'Low · today';
    if (index <= 5) return 'Moderate · today';
    if (index <= 7) return 'High · today';
    if (index <= 10) return 'Very high · today';
    return 'Extreme · today';
  }

  function renderMetrics(weather, todayIndex) {
    const current = weather.current || {};
    const daily = weather.daily || {};
    const hourlyIndex = nearestHourIndex(weather);
    const humidity = safeNumber(current.relative_humidity_2m);
    const windSpeed = safeNumber(current.wind_speed_10m);
    const windDirection = compassDirection(current.wind_direction_10m);
    const probability = safeNumber(weather.hourly?.precipitation_probability?.[hourlyIndex]);
    const uv = daily.uv_index_max?.[todayIndex];

    setText(elements.humidityValue, humidity === null ? '—' : `${Math.round(humidity)}%`);
    setText(
      elements.humidityNote,
      humidity === null ? 'Relative humidity' : humidity >= 75 ? 'Humid conditions' : humidity >= 50 ? 'Balanced moisture' : 'Dry air',
    );
    setText(elements.windValue, formatWindSpeed(windSpeed));
    const windStrength = windSpeed === null ? 'Surface wind' : windSpeed < 2 ? 'Calm' : windSpeed < 15 ? 'Gentle breeze' : windSpeed < 30 ? 'Moderate breeze' : 'Strong wind';
    setText(elements.windNote, [windDirection, windStrength].filter(Boolean).join(' · '));
    setText(elements.rainValue, probability === null ? '—' : `${Math.round(probability)}%`);
    setText(elements.rainNote, probability === null ? 'Next hour' : probability > 0 ? 'Possible in the next hour' : 'No rain expected · next hour');
    setText(elements.uvValue, formatDecimal(uv));
    setText(elements.uvNote, uvDescription(uv));
  }

  function renderHourly(weather) {
    const hourly = weather.hourly || {};
    const times = hourly.time || [];
    if (!times.length) {
      elements.hourlyForecast.innerHTML = '<p class="loading-note">Hourly forecast unavailable.</p>';
      return;
    }

    const start = nearestHourIndex(weather);
    const count = Math.min(7, times.length - start);
    const items = [];
    for (let offset = 0; offset < count; offset += 1) {
      const index = start + offset;
      const isNow = offset === 0;
      const day = Number(hourly.is_day?.[index]) !== 0;
      const info = weatherInfo(hourly.weather_code?.[index], day);
      const rainChance = safeNumber(hourly.precipitation_probability?.[index]);
      const chanceLabel = rainChance === null ? '—' : `${Math.round(rainChance)}%`;
      const dryClass = rainChance === null || rainChance === 0 ? ' is-dry' : '';
      const label = isNow ? 'Now' : formatForecastTime(times[index]);

      items.push(`
        <div class="hour-item${isNow ? ' is-now' : ''}">
          <span class="hour-time">${label}</span>
          <span class="hour-icon">${weatherIcon(info.icon)}</span>
          <span class="hour-temperature">${formatTemperature(hourly.temperature_2m?.[index])}</span>
          <span class="hour-rain${dryClass}">
            <svg viewBox="0 0 12 12" aria-hidden="true"><path d="M6 1.5S2.8 5.2 2.8 7.5a3.2 3.2 0 0 0 6.4 0C9.2 5.2 6 1.5 6 1.5Z" /></svg>
            ${chanceLabel}
          </span>
        </div>
      `);
    }
    elements.hourlyForecast.innerHTML = items.join('');
  }

  function renderDaily(weather) {
    const daily = weather.daily || {};
    const dates = daily.time || [];
    if (!dates.length) {
      elements.dailyForecast.innerHTML = '<p class="loading-note">Weekly forecast unavailable.</p>';
      return;
    }

    const lows = daily.temperature_2m_min || [];
    const highs = daily.temperature_2m_max || [];
    const validTemps = [...lows, ...highs].map(safeNumber).filter((value) => value !== null);
    const rangeMin = validTemps.length ? Math.min(...validTemps) : 0;
    const rangeMax = validTemps.length ? Math.max(...validTemps) : 1;
    const rangeSpan = Math.max(1, rangeMax - rangeMin);

    const rows = dates.slice(0, 7).map((date, index) => {
      const low = safeNumber(lows[index]);
      const high = safeNumber(highs[index]);
      const start = low === null ? 0 : ((low - rangeMin) / rangeSpan) * 100;
      const end = high === null ? 100 : ((high - rangeMin) / rangeSpan) * 100;
      const width = Math.max(9, end - start);
      const left = Math.min(start, 100 - width);
      const info = weatherInfo(daily.weather_code?.[index], true);
      const rain = safeNumber(daily.precipitation_probability_max?.[index]);
      const rainLabel = rain !== null && rain > 0 ? `<span class="daily-rain">${Math.round(rain)}%</span>` : '';
      const dayLabel = index === 0 ? 'Today' : formatForecastWeekday(date);
      const dateLabel = index === 0 ? '' : formatForecastDate(date);

      return `
        <div class="daily-row${index === 0 ? ' is-today' : ''}">
          <span class="daily-day">
            <span class="day-name">${dayLabel}</span>
            ${dateLabel ? `<span class="day-date">${dateLabel}</span>` : ''}
          </span>
          <span class="daily-condition">${weatherIcon(info.icon)}${rainLabel}</span>
          <span class="daily-temp">${formatTemperature(low)}</span>
          <span class="temp-range-track" aria-hidden="true">
            <span class="temp-range-fill" style="left:${left.toFixed(1)}%;width:${Math.min(width, 100 - left).toFixed(1)}%"></span>
          </span>
          <span class="daily-temp is-high">${formatTemperature(high)}</span>
        </div>
      `;
    });
    elements.dailyForecast.innerHTML = rows.join('');
  }

  function airQualityLevel(index) {
    if (index === null) {
      return {
        label: 'AQI unavailable',
        level: 'unknown',
        advice: 'An AQI reading is not available for this location. Pollutant levels may still be shown.',
      };
    }
    if (index <= 50) {
      return { label: 'Good', level: 'good', advice: 'Air quality is satisfactory for most people.' };
    }
    if (index <= 100) {
      return { label: 'Moderate', level: 'moderate', advice: 'Sensitive individuals may wish to reduce prolonged outdoor exertion.' };
    }
    if (index <= 150) {
      return { label: 'Unhealthy for sensitive groups', level: 'sensitive', advice: 'Sensitive groups should limit prolonged or heavy outdoor exertion.' };
    }
    if (index <= 200) {
      return { label: 'Unhealthy', level: 'unhealthy', advice: 'Consider limiting prolonged outdoor activity and follow local guidance.' };
    }
    if (index <= 300) {
      return { label: 'Very unhealthy', level: 'very-unhealthy', advice: 'Reduce outdoor exposure and follow local public-health guidance.' };
    }
    return { label: 'Hazardous', level: 'hazardous', advice: 'Avoid outdoor activity where possible and follow local public-health alerts.' };
  }

  function renderAirQuality() {
    const current = state.airQuality?.current || null;
    elements.aqiMarker.style.display = 'none';

    if (!current) {
      elements.airQualityPanel.dataset.airLevel = 'unknown';
      setText(elements.usAqi, '—');
      setText(elements.airCategory, state.isAirLoading ? 'Checking…' : 'Unavailable');
      setText(elements.airAdvice, state.isAirLoading
        ? 'Checking local air quality…'
        : 'Air-quality data is unavailable right now. Try again later.');
      setText(elements.pm25Value, '—');
      setText(elements.pm10Value, '—');
      setText(elements.ozoneValue, '—');
      setText(elements.nitrogenDioxideValue, '—');
      setText(elements.airQualityUpdated, state.isAirLoading ? 'UPDATING' : 'DATA UNAVAILABLE');
      return;
    }

    const aqi = safeNumber(current.us_aqi);
    const category = airQualityLevel(aqi);
    elements.airQualityPanel.dataset.airLevel = category.level;
    setText(elements.usAqi, aqi === null ? '—' : String(Math.round(aqi)));
    setText(elements.airCategory, category.label);
    setText(elements.airAdvice, category.advice);
    setText(elements.pm25Value, formatDecimal(current.pm2_5));
    setText(elements.pm10Value, formatDecimal(current.pm10));
    setText(elements.ozoneValue, formatDecimal(current.ozone));
    setText(elements.nitrogenDioxideValue, formatDecimal(current.nitrogen_dioxide));

    if (aqi !== null) {
      const position = Math.max(0, Math.min(aqi, 500)) / 5;
      elements.aqiMarker.style.left = `${position}%`;
      elements.aqiMarker.style.display = '';
    }

    const timestamp = current.time ? formatForecastTime(current.time) : '';
    const prefix = state.isAirLoading
      ? (state.airQuality ? 'SAVED' : 'UPDATING')
      : state.airStatus.tone === 'offline' ? 'SAVED' : 'MODEL';
    setText(elements.airQualityUpdated, timestamp ? `${prefix} · ${timestamp}` : prefix);
  }

  function renderWeather() {
    const hasWeather = Boolean(state.weather?.current && state.weather?.daily && state.weather?.hourly);
    elements.weatherAlert.hidden = hasWeather || state.isLoading;
    if (!hasWeather) {
      setText(elements.currentTemperature, '—');
      setText(elements.currentUnit, state.unit.toUpperCase());
      setText(elements.currentCondition, state.isLoading ? 'Loading forecast' : 'Forecast unavailable');
      setText(elements.feelsLikeTemperature, '—');
      elements.temperatureAccessibleLabel.setAttribute('aria-label', 'Current temperature unavailable');
      elements.heroWeatherIcon.innerHTML = weatherIcon('cloudy');
      setText(elements.todayHigh, '—');
      setText(elements.todayLow, '—');
      setText(elements.sunTimes, 'Sunrise — · Sunset —');
      setText(elements.humidityValue, '—');
      setText(elements.humidityNote, 'Relative humidity');
      setText(elements.windValue, '—');
      setText(elements.windNote, 'Surface wind');
      setText(elements.rainValue, '—');
      setText(elements.rainNote, 'Next hour');
      setText(elements.uvValue, '—');
      setText(elements.uvNote, "Today's peak");
      showForecastPlaceholder(state.isLoading ? 'Loading forecast…' : 'Forecast unavailable. Try again.');
      if (!state.isLoading) {
        setText(elements.weatherAlertText, 'Could not load weather data. Check your connection, then try again.');
      }
      return;
    }

    renderCurrent(state.weather);
    renderHourly(state.weather);
    renderDaily(state.weather);
  }

  function renderAll() {
    renderLocation();
    updateUnitButtons();
    renderWeather();
    renderAirQuality();
    setStatus(state.status.tone, state.status.label);
  }

  function showToast(message) {
    setText(elements.toastMessage, message);
    elements.toast.hidden = false;
    window.clearTimeout(state.toastTimer);
    state.toastTimer = window.setTimeout(() => {
      elements.toast.hidden = true;
    }, 4600);
  }

  function hideSearchResults() {
    elements.searchResults.hidden = true;
    elements.searchInput.setAttribute('aria-expanded', 'false');
    elements.searchInput.removeAttribute('aria-activedescendant');
    state.activeSearchIndex = -1;
  }

  function openSearchResults() {
    elements.searchResults.hidden = false;
    elements.searchInput.setAttribute('aria-expanded', 'true');
  }

  function placeDetail(place) {
    const parts = [place.admin1, place.country]
      .filter((part, index, values) => part && values.indexOf(part) === index && part !== place.name);
    return parts.join(' · ') || 'Weather location';
  }

  function drawSearchResults(message = '') {
    elements.searchResults.replaceChildren();
    if (!state.searchResults.length) {
      const empty = document.createElement('div');
      empty.className = 'search-empty';
      empty.textContent = message || 'No matching places found.';
      elements.searchResults.append(empty);
      openSearchResults();
      return;
    }

    state.searchResults.forEach((place, index) => {
      const option = document.createElement('button');
      option.className = `search-result${index === state.activeSearchIndex ? ' is-active' : ''}`;
      option.type = 'button';
      option.id = `search-option-${index}`;
      option.setAttribute('role', 'option');
      option.setAttribute('aria-selected', String(index === state.activeSearchIndex));
      option.dataset.placeIndex = String(index);

      const pin = document.createElement('span');
      pin.className = 'search-result-pin';
      pin.setAttribute('aria-hidden', 'true');
      pin.innerHTML = '<svg viewBox="0 0 24 24"><path d="M19 10.2c0 5-7 10.2-7 10.2S5 15.2 5 10.2a7 7 0 1 1 14 0Z"/><circle cx="12" cy="10" r="2.3"/></svg>';

      const copy = document.createElement('span');
      copy.className = 'search-result-copy';
      const name = document.createElement('span');
      name.className = 'search-result-name';
      name.textContent = place.name;
      const detail = document.createElement('span');
      detail.className = 'search-result-detail';
      detail.textContent = placeDetail(place);
      copy.append(name, detail);
      option.append(pin, copy);
      elements.searchResults.append(option);
    });

    if (state.activeSearchIndex >= 0) {
      elements.searchInput.setAttribute('aria-activedescendant', `search-option-${state.activeSearchIndex}`);
    } else {
      elements.searchInput.removeAttribute('aria-activedescendant');
    }
    openSearchResults();
  }

  function normalizeGeocodingResult(result) {
    return {
      id: String(result.id || `${result.latitude},${result.longitude}`),
      name: String(result.name || 'Unknown location'),
      admin1: String(result.admin1 || ''),
      country: String(result.country || ''),
      latitude: Number(result.latitude),
      longitude: Number(result.longitude),
      timezone: String(result.timezone || ''),
    };
  }

  async function searchPlaces(query) {
    if (state.searchController) state.searchController.abort();
    const controller = new AbortController();
    state.searchController = controller;
    const normalizedQuery = query.trim();
    if (normalizedQuery.length < 2) {
      state.searchResults = [];
      hideSearchResults();
      return;
    }

    state.searchResults = [];
    state.activeSearchIndex = -1;
    drawSearchResults('Searching places…');

    const params = new URLSearchParams({
      name: normalizedQuery,
      count: '6',
      language: 'en',
      format: 'json',
    });

    try {
      const response = await fetch(`${GEOCODING_API}?${params}`, { signal: controller.signal });
      if (!response.ok) throw new Error('Place search failed.');
      const data = await response.json();
      if (controller.signal.aborted || elements.searchInput.value.trim() !== normalizedQuery) return;
      state.searchResults = (data.results || [])
        .map(normalizeGeocodingResult)
        .filter(isValidPlace);
      drawSearchResults();
    } catch (error) {
      if (error.name === 'AbortError') return;
      if (elements.searchInput.value.trim() !== normalizedQuery) return;
      state.searchResults = [];
      drawSearchResults('City search is unavailable right now.');
    }
  }

  function handleSearchInput() {
    const query = elements.searchInput.value.trim();
    window.clearTimeout(state.searchTimer);
    if (state.searchController) state.searchController.abort();
    if (query.length < 2) {
      state.searchResults = [];
      hideSearchResults();
      return;
    }
    state.searchTimer = window.setTimeout(() => searchPlaces(query), 250);
  }

  function selectPlace(place) {
    if (!isValidPlace(place)) return;
    state.weatherRequestId += 1;
    if (state.weatherController) state.weatherController.abort();
    if (state.airQualityController) state.airQualityController.abort();
    state.place = {
      ...place,
      latitude: Number(place.latitude),
      longitude: Number(place.longitude),
    };
    writeStoredJson(PLACE_KEY, state.place);
    elements.searchInput.value = '';
    state.searchResults = [];
    hideSearchResults();

    const cached = readForecastCache(state.place);
    const cachedAir = readAirQualityCache(state.place);
    state.weather = cached ? cached.weather : null;
    state.airQuality = cachedAir ? cachedAir.airQuality : null;
    state.isLoading = Boolean(!cached);
    state.isAirLoading = Boolean(!cachedAir);
    state.status = cached
      ? { tone: 'offline', label: 'Saved forecast' }
      : { tone: 'loading', label: 'Connecting' };
    state.airStatus = cachedAir
      ? { tone: 'offline', label: 'Saved air data' }
      : { tone: 'loading', label: 'Checking air' };
    renderAll();
    fetchForecast(state.place);
  }

  async function fetchAirQuality(place = state.place) {
    if (!isValidPlace(place)) return;
    if (state.airQualityController) state.airQualityController.abort();
    const controller = new AbortController();
    state.airQualityController = controller;
    const requestId = ++state.airQualityRequestId;
    const timeout = window.setTimeout(() => controller.abort(), 15000);

    state.isAirLoading = true;
    state.airStatus = { tone: 'loading', label: state.airQuality ? 'Refreshing air' : 'Checking air' };
    renderAirQuality();

    const params = new URLSearchParams({
      latitude: Number(place.latitude).toFixed(4),
      longitude: Number(place.longitude).toFixed(4),
      current: 'us_aqi,pm2_5,pm10,ozone,nitrogen_dioxide',
      timezone: 'auto',
    });

    try {
      const response = await fetch(`${AIR_QUALITY_API}?${params}`, { signal: controller.signal });
      if (!response.ok) throw new Error('Air-quality service returned an error.');
      const data = await response.json();
      if (!data.current) throw new Error('Air-quality data was incomplete.');
      if (requestId !== state.airQualityRequestId) return;

      state.airQuality = data;
      state.isAirLoading = false;
      state.airStatus = { tone: 'live', label: 'Model data' };
      writeStoredJson(airQualityCacheKey(place), { airQuality: data, savedAt: Date.now() });
      renderAirQuality();
    } catch (error) {
      if (requestId !== state.airQualityRequestId) return;
      if (controller.signal.aborted && state.airQualityController !== controller) return;
      state.isAirLoading = false;
      state.airStatus = state.airQuality
        ? { tone: 'offline', label: 'Saved air data' }
        : { tone: 'error', label: 'Air data unavailable' };
      renderAirQuality();
    } finally {
      window.clearTimeout(timeout);
      if (requestId === state.airQualityRequestId) state.isAirLoading = false;
    }
  }

  async function fetchForecast(place = state.place) {
    if (!isValidPlace(place)) return;
    if (state.weatherController) state.weatherController.abort();
    const controller = new AbortController();
    state.weatherController = controller;
    const requestId = ++state.weatherRequestId;
    const timeout = window.setTimeout(() => controller.abort(), 15000);

    state.isLoading = true;
    state.status = { tone: 'loading', label: state.weather ? 'Refreshing' : 'Connecting' };
    elements.weatherAlert.hidden = true;
    setStatus(state.status.tone, state.status.label);
    fetchAirQuality(place);

    const params = new URLSearchParams({
      latitude: Number(place.latitude).toFixed(4),
      longitude: Number(place.longitude).toFixed(4),
      current: 'temperature_2m,relative_humidity_2m,apparent_temperature,is_day,precipitation,weather_code,wind_speed_10m,wind_direction_10m',
      hourly: 'temperature_2m,precipitation_probability,weather_code,is_day',
      daily: 'weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,uv_index_max,precipitation_probability_max',
      temperature_unit: 'celsius',
      wind_speed_unit: 'kmh',
      precipitation_unit: 'mm',
      timezone: 'auto',
      forecast_days: '7',
    });

    try {
      const response = await fetch(`${WEATHER_API}?${params}`, { signal: controller.signal });
      if (!response.ok) throw new Error('Weather service returned an error.');
      const data = await response.json();
      if (!data.current || !data.hourly || !data.daily) throw new Error('Weather data was incomplete.');
      if (requestId !== state.weatherRequestId) return;

      state.weather = data;
      state.isLoading = false;
      state.status = { tone: 'live', label: 'Live forecast' };
      if (!state.place.timezone && data.timezone) {
        state.place = { ...state.place, timezone: data.timezone };
        writeStoredJson(PLACE_KEY, state.place);
      }
      writeStoredJson(forecastCacheKey(place), { weather: data, savedAt: Date.now() });
      renderAll();
    } catch (error) {
      if (requestId !== state.weatherRequestId || error.name === 'AbortError' && !controller.signal.aborted) return;
      if (controller.signal.aborted && state.weatherController !== controller) return;
      state.isLoading = false;
      state.status = state.weather
        ? { tone: 'offline', label: 'Saved forecast' }
        : { tone: 'error', label: 'Unavailable' };
      renderAll();
    } finally {
      window.clearTimeout(timeout);
      if (requestId === state.weatherRequestId) {
        state.isLoading = false;
        elements.refreshButton.classList.remove('is-refreshing');
        elements.refreshButton.disabled = false;
      }
    }
  }

  function useCurrentLocation() {
    if (!navigator.geolocation) {
      showToast('Location access is not available in this browser.');
      return;
    }
    if (!window.isSecureContext) {
      showToast('Location access needs a secure connection (HTTPS or localhost).');
      return;
    }

    state.isLocating = true;
    elements.locateButton.disabled = true;
    navigator.geolocation.getCurrentPosition(
      ({ coords }) => {
        state.isLocating = false;
        const place = {
          id: `current-${coords.latitude.toFixed(3)}-${coords.longitude.toFixed(3)}`,
          name: 'My location',
          admin1: '',
          country: '',
          latitude: coords.latitude,
          longitude: coords.longitude,
          timezone: '',
        };
        elements.locateButton.disabled = false;
        selectPlace(place);
      },
      (error) => {
        state.isLocating = false;
        elements.locateButton.disabled = false;
        const message = error.code === error.PERMISSION_DENIED
          ? 'Location permission was not granted.'
          : error.code === error.TIMEOUT
            ? 'Could not find your location in time. Try again.'
            : 'Your location could not be determined.';
        showToast(message);
      },
      { enableHighAccuracy: false, maximumAge: 600000, timeout: 12000 },
    );
  }

  function clearToast() {
    window.clearTimeout(state.toastTimer);
    elements.toast.hidden = true;
  }

  function setupInstallPrompt() {
    window.addEventListener('beforeinstallprompt', (event) => {
      event.preventDefault();
      state.installPrompt = event;
      elements.installButton.hidden = false;
    });
    window.addEventListener('appinstalled', () => {
      state.installPrompt = null;
      elements.installButton.hidden = true;
      showToast('Omarchy Weather was added to your applications.');
    });
    elements.installButton.addEventListener('click', async () => {
      if (!state.installPrompt) return;
      state.installPrompt.prompt();
      await state.installPrompt.userChoice;
      state.installPrompt = null;
      elements.installButton.hidden = true;
    });
  }

  elements.searchForm.addEventListener('submit', (event) => {
    event.preventDefault();
    const query = elements.searchInput.value.trim();
    if (state.searchResults.length) {
      const selectedIndex = state.activeSearchIndex >= 0 ? state.activeSearchIndex : 0;
      selectPlace(state.searchResults[selectedIndex]);
    } else if (query.length >= 2) {
      searchPlaces(query);
    }
  });

  elements.searchInput.addEventListener('input', handleSearchInput);
  elements.searchInput.addEventListener('keydown', (event) => {
    if (event.key === 'ArrowDown' && !elements.searchResults.hidden && state.searchResults.length) {
      event.preventDefault();
      state.activeSearchIndex = (state.activeSearchIndex + 1) % state.searchResults.length;
      drawSearchResults();
    } else if (event.key === 'ArrowUp' && !elements.searchResults.hidden && state.searchResults.length) {
      event.preventDefault();
      state.activeSearchIndex = state.activeSearchIndex <= 0
        ? state.searchResults.length - 1
        : state.activeSearchIndex - 1;
      drawSearchResults();
    } else if (event.key === 'Escape') {
      hideSearchResults();
    }
  });

  elements.searchResults.addEventListener('click', (event) => {
    const option = event.target.closest('[data-place-index]');
    if (!option) return;
    selectPlace(state.searchResults[Number(option.dataset.placeIndex)]);
  });

  document.addEventListener('click', (event) => {
    if (!elements.searchForm.contains(event.target)) hideSearchResults();
  });

  document.addEventListener('keydown', (event) => {
    const isEditable = event.target instanceof HTMLElement && (
      event.target.isContentEditable || ['INPUT', 'TEXTAREA', 'SELECT'].includes(event.target.tagName)
    );
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'k') {
      event.preventDefault();
      elements.searchInput.focus();
      elements.searchInput.select();
    } else if (event.key === '/' && !isEditable) {
      event.preventDefault();
      elements.searchInput.focus();
    }
  });

  document.querySelectorAll('[data-unit]').forEach((button) => {
    button.addEventListener('click', () => {
      const unit = button.dataset.unit;
      if (unit !== 'c' && unit !== 'f') return;
      state.unit = unit;
      try {
        window.localStorage.setItem(UNIT_KEY, unit);
      } catch {
        // The selection remains active for this session.
      }
      updateUnitButtons();
      renderWeather();
    });
  });

  elements.refreshButton.addEventListener('click', () => fetchForecast(state.place));
  elements.retryButton.addEventListener('click', () => fetchForecast(state.place));
  elements.locateButton.addEventListener('click', useCurrentLocation);
  elements.toastClose.addEventListener('click', clearToast);

  setupInstallPrompt();

  const cachedForecast = readForecastCache(state.place);
  const cachedAirQuality = readAirQualityCache(state.place);
  if (cachedForecast) {
    state.weather = cachedForecast.weather;
    state.status = { tone: 'offline', label: 'Saved forecast' };
  }
  if (cachedAirQuality) {
    state.airQuality = cachedAirQuality.airQuality;
    state.airStatus = { tone: 'offline', label: 'Saved air data' };
  }
  state.isLoading = true;
  renderAll();
  fetchForecast(state.place);
  window.setInterval(updateLocalClock, 30000);
  window.setInterval(() => {
    if (!document.hidden) fetchForecast(state.place);
  }, 30 * 60 * 1000);

  if ('serviceWorker' in navigator && /^https?:$/.test(window.location.protocol)) {
    window.addEventListener('load', () => {
      navigator.serviceWorker.register('./service-worker.js').catch(() => {
        // The app remains fully usable if service workers are unavailable.
      });
    });
  }
})();
