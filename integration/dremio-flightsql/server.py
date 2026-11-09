"""A TLS Flight SQL contract fixture, not a Dremio implementation."""

import argparse
import datetime
import json
import pathlib
import threading
import uuid

import adbc_driver_flightsql
import pyarrow as pa
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID
from google.protobuf import descriptor_pb2, descriptor_pool, message_factory
from google.protobuf.any_pb2 import Any
from pyarrow import flight


def messages():
    """Define only the public Flight SQL messages exercised by this fixture."""
    file = descriptor_pb2.FileDescriptorProto(
        name="fixture.proto", package="arrow.flight.protocol.sql", syntax="proto3"
    )
    fields = {
        "CommandStatementQuery": [("query", 1, 9)],
        "CommandPreparedStatementQuery": [("prepared_statement_handle", 1, 12)],
        "ActionCreatePreparedStatementRequest": [("query", 1, 9)],
        "ActionCreatePreparedStatementResult": [
            ("prepared_statement_handle", 1, 12),
            ("dataset_schema", 2, 12),
            ("parameter_schema", 3, 12),
        ],
        "ActionClosePreparedStatementRequest": [("prepared_statement_handle", 1, 12)],
        "DoPutPreparedStatementResult": [("prepared_statement_handle", 1, 12)],
    }
    for name, definitions in fields.items():
        message = file.message_type.add(name=name)
        for field_name, number, field_type in definitions:
            message.field.add(name=field_name, number=number, type=field_type, label=1)
    pool = descriptor_pool.DescriptorPool()
    pool.Add(file)
    return {
        name: message_factory.GetMessageClass(
            pool.FindMessageTypeByName("arrow.flight.protocol.sql." + name)
        )
        for name in fields
    }


MESSAGES = messages()


def unpack(value):
    wrapper = Any.FromString(value)
    name = wrapper.TypeName().split(".")[-1]
    if name not in MESSAGES:
        raise NotImplementedError(name)
    return name, MESSAGES[name].FromString(wrapper.value)


def pack(message):
    wrapper = Any()
    wrapper.Pack(message)
    return wrapper.SerializeToString()


class Auth(flight.ServerMiddleware):
    def __init__(self, user):
        self.user = user


class AuthFactory(flight.ServerMiddlewareFactory):
    def __init__(self, log):
        self.log = log
        self.lock = threading.Lock()

    def start_call(self, info, headers):
        values = headers.get("authorization", [])
        credential = values[0] if len(values) == 1 else ""
        if isinstance(credential, bytes):
            credential = credential.decode("ascii")
        users = {
            "Bearer fixture-A": "alice",
            "Bearer renewed-A": "alice",
            "Bearer fixture-A-acquired": "alice",
            "Bearer fixture-B": "bob",
        }
        user = users.get(credential)
        with self.lock, self.log.open("a", encoding="utf-8") as stream:
            # Only the synthetic allowlisted fixture labels are recorded.
            stream.write(
                json.dumps(
                    {
                        "method": str(info.method),
                        "user": user,
                        "credential": credential if user else "rejected",
                    }
                )
                + "\n"
            )
        if not user:
            raise flight.FlightUnauthenticatedError("Fixture bearer rejected")
        return Auth(user)


class Server(flight.FlightServerBase):
    def __init__(self, cert, key, log):
        super().__init__(
            location=("127.0.0.1", 0),
            tls_certificates=[(cert, key)],
            middleware={"auth": AuthFactory(log)},
        )
        self.prepared = {}
        self.results = {}

    def table(self, user, query, parameter=None):
        if "denied" in query.lower():
            raise flight.FlightUnauthorizedError("Fixture permission denied")
        if "?" in query:
            value = parameter if parameter is not None else 0
            return pa.table({"value": pa.array([value], type=pa.int64())})
        return pa.table({"database_user": [user], "value": [42]})

    def do_action(self, context, action):
        user = context.get_middleware("auth").user
        _, request = unpack(action.body.to_pybytes())
        if action.type == "CreatePreparedStatement":
            handle = uuid.uuid4().hex.encode()
            self.prepared[handle] = (user, request.query, None)
            table = self.table(user, request.query)
            parameters = (
                pa.schema([("parameter", pa.int64())])
                if "?" in request.query
                else pa.schema([])
            )
            response = MESSAGES["ActionCreatePreparedStatementResult"](
                prepared_statement_handle=handle,
                dataset_schema=table.schema.serialize().to_pybytes(),
                parameter_schema=parameters.serialize().to_pybytes(),
            )
            yield flight.Result(pack(response))
        elif action.type == "ClosePreparedStatement":
            self.prepared.pop(request.prepared_statement_handle, None)
        else:
            raise NotImplementedError(action.type)

    def get_flight_info(self, context, descriptor):
        user = context.get_middleware("auth").user
        name, request = unpack(descriptor.command)
        if name == "CommandStatementQuery":
            table = self.table(user, request.query)
        elif name == "CommandPreparedStatementQuery":
            owner, query, parameter = self.prepared[request.prepared_statement_handle]
            if owner != user:
                raise flight.FlightUnauthorizedError("Fixture owner mismatch")
            table = self.table(user, query, parameter)
        else:
            raise NotImplementedError(name)
        ticket = uuid.uuid4().hex.encode()
        self.results[ticket] = (user, table)
        endpoint = flight.FlightEndpoint(flight.Ticket(ticket), [])
        return flight.FlightInfo(table.schema, descriptor, [endpoint], len(table), -1)

    def do_get(self, context, ticket):
        user = context.get_middleware("auth").user
        owner, table = self.results.pop(ticket.ticket)
        if owner != user:
            raise flight.FlightUnauthorizedError("Fixture result owner mismatch")
        return flight.RecordBatchStream(table)

    def do_put(self, context, descriptor, reader, writer):
        user = context.get_middleware("auth").user
        _, request = unpack(descriptor.command)
        handle = request.prepared_statement_handle
        owner, query, _ = self.prepared[handle]
        if owner != user:
            raise flight.FlightUnauthorizedError("Fixture statement owner mismatch")
        table = reader.read_all()
        self.prepared[handle] = (user, query, table.column(0)[0].as_py())
        result = MESSAGES["DoPutPreparedStatementResult"](
            prepared_statement_handle=handle
        )
        writer.write(result.SerializeToString())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "localhost")])
    now = datetime.datetime.now(datetime.UTC)
    cert = (
        x509.CertificateBuilder()
        .subject_name(name)
        .issuer_name(name)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(minutes=1))
        .not_valid_after(now + datetime.timedelta(days=1))
        .add_extension(
            x509.SubjectAlternativeName([x509.DNSName("localhost")]), critical=False
        )
        .add_extension(x509.BasicConstraints(ca=True, path_length=None), critical=True)
        .sign(key, hashes.SHA256())
        .public_bytes(serialization.Encoding.PEM)
    )
    private = key.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    )
    ca = args.output / "ca.pem"
    ca.write_bytes(cert)
    server = Server(cert, private, args.output / "requests.jsonl")
    (args.output / "ready.json").write_text(
        json.dumps(
            {
                "port": server.port,
                "ca_bundle": str(ca),
                "driver": adbc_driver_flightsql._driver_path(),
            }
        ),
        encoding="utf-8",
    )
    server.serve()


if __name__ == "__main__":
    main()
