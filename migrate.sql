CREATE TABLE karma (
  id INTEGER PRIMARY KEY,
  channel TEXT NOT NULL,
  name TEXT NOT NULL,
  total INTEGER NOT NULL DEFAULT 0,
  plus  INTEGER NOT NULL DEFAULT 0,
  minus INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX karma_channel_name ON karma(channel,name);

CREATE TABLE 'msg' (
  id INTEGER PRIMARY KEY,
  channel TEXT NOT NULL,
  from_name TEXT NOT NULL,
  to_name TEXT NOT NULL, body TEXT NOT NULL DEFAULT ''
);
CREATE INDEX msgs_channel_name ON 'msg'(channel,to_name);

CREATE TABLE timer (
  id INTEGER PRIMARY KEY,
  channel TEXT NOT NULL,
  hour INTEGER NOT NULL,
  minute INTEGER NOT NULL,
  body TEXT NOT NULL,
  last_sent INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX timer_channel_hour_minute ON timer(channel, hour, minute);

