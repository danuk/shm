UPDATE spool SET event='{"title":"send forecasts","kind":"Jobs","method":"job_make_forecasts","period":"86400"}' WHERE event->"$.title"="send forecasts";

