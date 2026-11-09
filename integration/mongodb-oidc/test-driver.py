"""Exercise the public PyMongo callback API without network credentials."""

import pathlib
import sys
import unittest
from unittest.mock import MagicMock, patch

from pymongo.auth_oidc import OIDCCallbackContext, OIDCIdPInfo
from pymongo.errors import OperationFailure

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "inst/python"))
sys.dont_write_bytecode = True
import shiny_oauthdb_mongodb as adapter


class DriverTests(unittest.TestCase):
    def test_callback_checks_issuer_and_client_without_refresh_credentials(self):
        callback = adapter._VisitorToken("visitor-jwt", "https://issuer", "app")
        context = OIDCCallbackContext(5, "alice", 1,
                                      idp_info=OIDCIdPInfo("https://issuer", "app"))
        result = callback.fetch(context)
        self.assertEqual(result.access_token, "visitor-jwt")
        self.assertIsNone(result.refresh_token)
        for info in [None, OIDCIdPInfo("https://other", "app"), OIDCIdPInfo("https://issuer", "other")]:
            context.idp_info = info
            with self.assertRaises(ValueError):
                callback.fetch(context)
        self.assertNotIn("visitor-jwt", repr(callback))

    @patch.object(adapter.pymongo, "MongoClient")
    def test_client_requires_visitor_tokens_and_verified_tls(self, constructor):
        client = adapter.Client("visitor-jwt", "mongodb://mongo", "reports",
                                "https://issuer", None, None, ["mongo"], 5, None)
        options = constructor.call_args.kwargs
        self.assertEqual(options["authMechanism"], "MONGODB-OIDC")
        self.assertEqual(options["authSource"], "$external")
        self.assertEqual(options["authMechanismProperties"]["ALLOWED_HOSTS"], ["mongo"])
        self.assertNotIn("ENVIRONMENT", options["authMechanismProperties"])
        self.assertTrue(options["tls"])
        for option in ["tlsAllowInvalidCertificates", "tlsAllowInvalidHostnames", "retryReads", "retryWrites"]:
            self.assertFalse(options[option])
        client.close()
        client.close()
        constructor.return_value.close.assert_called_once()
        self.assertIsNone(client._callback._token)
        self.assertFalse(client.execute("run", {"command": '{"ping":1}'})["ok"])

    @patch.object(adapter.pymongo, "MongoClient")
    def test_failure_does_not_replay_or_expose_server_text(self, constructor):
        client = adapter.Client("visitor-jwt", "mongodb://mongo", "reports",
                                "https://issuer", None, None, ["mongo"], 5, None)
        database = constructor.return_value.__getitem__.return_value
        database.command.side_effect = OperationFailure("echoed visitor-jwt", code=13)
        response = client.execute("run", {"command": '{"insert":"orders","documents":[]}'})
        self.assertEqual(response, {"ok": False, "code": 13})
        database.command.assert_called_once()

    @patch.object(adapter.pymongo, "MongoClient")
    def test_find_closes_cursor_on_success_and_failure(self, constructor):
        client = adapter.Client("visitor-jwt", "mongodb://mongo", "reports",
                                "https://issuer", None, None, ["mongo"], 5, None)
        database = constructor.return_value.__getitem__.return_value
        cursor = MagicMock()
        database.__getitem__.return_value.find.return_value = cursor
        args = dict(collection="orders", filter="{}", projection="{}", sort="{}", skip=0, limit=10)
        cursor.__iter__.return_value = iter([{"n": 1}])
        self.assertTrue(client.execute("find", args)["ok"])
        cursor.close.assert_called_once()
        cursor.close.reset_mock()
        cursor.__iter__.side_effect = OperationFailure("secret", code=13)
        self.assertFalse(client.execute("find", args)["ok"])
        cursor.close.assert_called_once()


if __name__ == "__main__":
    unittest.main()
