-- Index for forecast_candidates query in Core::Pay
-- SQL::Abstract orders WHERE fields alphabetically:
--   auto_bill (eq) → expire (range) → status (IN) → withdraw_id (eq)
-- To let the optimizer use all equality columns before the range scan,
-- the index reorders them: equalities first, range (expire) last.
ALTER TABLE `user_services`
    ADD KEY `idx_forecast_candidates` (`auto_bill`, `status`, `withdraw_id`, `expire`, `user_id`);
