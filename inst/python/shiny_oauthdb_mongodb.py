"""PyMongo boundary for shinyOAuthDB. No R callbacks run in driver threads."""

import pymongo
from bson import json_util
from pymongo.auth_oidc import OIDCCallback, OIDCCallbackResult
from pymongo.errors import PyMongoError


class _VisitorToken(OIDCCallback):
    def __init__(self, token, issuer, client_id):
        self._token = token
        self._issuer = issuer
        self._client_id = client_id

    def fetch(self, context):
        info = context.idp_info
        if info is None or info.issuer != self._issuer:
            raise ValueError("MongoDB OIDC issuer does not match the configured issuer")
        if self._client_id is not None and info.clientId != self._client_id:
            raise ValueError("MongoDB OIDC client ID does not match the configured client")
        return OIDCCallbackResult(access_token=self._token)

    def __repr__(self):
        return "<shinyOAuthDB visitor token>"


class Client:
    def __init__(self, token, url, db, issuer, user, client_id, hosts, timeout, ca_bundle):
        if pymongo.version_tuple[:2] < (4, 10):
            raise ValueError("shinyOAuthDB requires PyMongo >= 4.10")
        callback = _VisitorToken(token, issuer, client_id)
        options = dict(
            authMechanism="MONGODB-OIDC",
            authSource="$external",
            authMechanismProperties={
                "OIDC_HUMAN_CALLBACK": callback,
                "ALLOWED_HOSTS": list(hosts),
            },
            tls=True,
            tlsAllowInvalidCertificates=False,
            tlsAllowInvalidHostnames=False,
            retryReads=False,
            retryWrites=False,
            timeoutMS=timeout * 1000,
            serverSelectionTimeoutMS=timeout * 1000,
            connectTimeoutMS=timeout * 1000,
            socketTimeoutMS=timeout * 1000,
            connect=False,
        )
        if user is not None:
            options["username"] = user
        if ca_bundle is not None:
            options["tlsCAFile"] = ca_bundle
        self._client = pymongo.MongoClient(url, **options)
        self._db = self._client[db]
        self._timeout = timeout
        self._callback = callback
        self._closed = False

    def execute(self, operation, arguments):
        if self._closed:
            return {"ok": False, "code": None}
        try:
            with pymongo.timeout(self._timeout):
                result = self._execute(operation, arguments)
            return {"ok": True, "json": json_util.dumps(result)}
        except (PyMongoError, ValueError, TypeError, OverflowError) as error:
            # Driver messages can contain server-controlled text or credentials.
            # Return a numeric code without retaining the exception in R.
            code = getattr(error, "code", None)
            return {"ok": False, "code": code if isinstance(code, int) else None}

    def _execute(self, operation, args):
        if operation == "find":
            collection = self._db[args["collection"]]
            cursor = collection.find(
                json_util.loads(args["filter"]),
                projection=json_util.loads(args["projection"]),
                skip=args["skip"],
                limit=args["limit"],
            )
            try:
                ordering = json_util.loads(args["sort"])
                if ordering:
                    cursor.sort(list(ordering.items()))
                return list(cursor)
            finally:
                cursor.close()
        if operation == "aggregate":
            with self._db[args["collection"]].aggregate(
                json_util.loads(args["pipeline"])
            ) as cursor:
                return list(cursor)
        if operation == "count":
            return self._db[args["collection"]].count_documents(
                json_util.loads(args["filter"])
            )
        if operation == "run":
            command = json_util.loads(args["command"])
            excluded = {
                "authenticate", "saslstart", "saslcontinue", "logout",
                "getmore", "killcursors", "find", "aggregate", "listcollections",
                "bulkwrite", "parallelcollectionscan", "speculativeauthenticate",
                "listindexes", "startsession", "endsessions", "refreshsessions",
                "committransaction", "aborttransaction", "lsid", "txnnumber",
                "autocommit", "starttransaction", "$db",
            }
            if not command or any(key.lower() in excluded for key in command):
                raise ValueError("Use the read methods for cursors; authentication and transactions are managed")
            return self._db.command(command)
        raise ValueError("Unknown MongoDB operation")

    def close(self):
        if not self._closed:
            self._closed = True
            self._callback._token = None
            self._client.close()

    def __repr__(self):
        return "<shinyOAuthDB MongoDB client>"
