-- Point-only and fully discounted returns still need a refund ledger.
USE `shupick_v2`;
ALTER TABLE refunds DROP CHECK chk_refunds_amount,
  ADD CONSTRAINT chk_refunds_amount CHECK (refund_amount >= 0);
ALTER TABLE refund_items DROP CHECK chk_refund_items_amount,
  ADD CONSTRAINT chk_refund_items_amount CHECK (refund_amount >= 0);
