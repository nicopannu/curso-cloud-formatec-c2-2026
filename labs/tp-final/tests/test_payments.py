import os
import sys
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../app/pagos")))
import app as payments_app  # noqa: E402


class PaymentApiTests(unittest.TestCase):
    def setUp(self):
        self.client = payments_app.app.test_client()
        os.environ["NOTIFICATIONS_URL"] = "http://notifications.test/notify"
        os.environ["NOTIFICATION_TIMEOUT_SECONDS"] = "1.5"

    def tearDown(self):
        os.environ.pop("NOTIFICATIONS_URL", None)
        os.environ.pop("NOTIFICATION_TIMEOUT_SECONDS", None)

    @patch("app.requests.post")
    def test_payment_is_accepted_when_notification_succeeds(self, post):
        post.return_value = Mock(status_code=202)
        response = self.client.post("/payments", json={"payment_id": "p-123"})
        self.assertEqual(response.status_code, 202)
        self.assertEqual(response.json["payment_status"], "accepted")
        self.assertEqual(response.json["notification_status"], "sent")
        self.assertEqual(post.call_args.kwargs["timeout"], 1.5)

    @patch("app.requests.post", side_effect=payments_app.requests.exceptions.Timeout)
    def test_notification_timeout_does_not_fail_the_synthetic_payment(self, post):
        response = self.client.post("/payments", json={"payment_id": "p-456"})
        self.assertEqual(response.status_code, 202)
        self.assertEqual(response.json["payment_status"], "accepted")
        self.assertEqual(response.json["notification_status"], "deferred_timeout")
        self.assertEqual(post.call_args.kwargs["timeout"], 1.5)

    @patch("app.requests.post")
    def test_zero_timeout_reproduces_unbounded_legacy_wait(self, post):
        os.environ["NOTIFICATION_TIMEOUT_SECONDS"] = "0"
        post.return_value = Mock(status_code=202)
        response = self.client.post("/payments", json={"payment_id": "p-789"})
        self.assertEqual(response.status_code, 202)
        self.assertIsNone(post.call_args.kwargs["timeout"])

    @patch("app.requests.post")
    def test_in_flight_metric_returns_to_zero_after_response(self, post):
        post.return_value = Mock(status_code=202)
        self.client.post("/payments", json={"payment_id": "p-metric"})
        self.assertEqual(payments_app.IN_FLIGHT.labels(service="payments")._value.get(), 0)


if __name__ == "__main__":
    unittest.main()
