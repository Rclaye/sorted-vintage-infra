"""Part of verify_sprint3.sh (T075): a scripted purchase and a declined card in sv-dev.

Runs on the lab host as bot, workstation mode only (it writes to sv-dev), in the venv the load
test uses (the seed service's pinned libraries) with the seed service on PYTHONPATH: it signs in
through the BFF login form like a browser with the seed job's code (services/seed/app/site.py).

The verify seller lists two small items; the verify buyer checks out each through the BFF and the
PaymentIntent is confirmed with Stripe's test cards using the sandbox key (read from Secret
stripe, never printed): pm_card_visa must end `paid` with a balanced ledger, two emails and the
item sold; pm_card_chargeDeclined must end `failed`, put the item back on sale and send nothing.
The declined item is deleted afterwards. Finally a malformed order event is published to the
orders exchange and must reach notifications.orders.dead (FR-017, the live half of 3.6's check).

Prints PASS and FAIL lines like the shell checks; exits 1 on the first failure.
"""

import base64
import json
import re
import subprocess
import sys
import time
import uuid
from html import unescape

import httpx
from app import photos
from app.site import LabTransport, Site, pinned_context

SITE = "https://dev.sortedvtg.lan:8443"
STRIPE = "https://api.stripe.com/v1"
CONTEXT = ["kubectl", "--context", "kind-sorted-vintage", "-n", "sv-dev"]


def ok(message: str) -> None:
    print(f"  \033[32mPASS\033[0m {message}", flush=True)


def fail(message: str) -> None:
    print(f"  \033[31mFAIL\033[0m {message}", flush=True)
    sys.exit(1)


def kubectl(*args: str) -> str:
    return subprocess.run([*CONTEXT, *args], capture_output=True, text=True, check=True).stdout


def secret(name: str, key: str) -> str:
    return base64.b64decode(kubectl("get", "secret", name, "-o", f"jsonpath={{.data.{key}}}")).decode()


def sql(db: str, query: str) -> list[list[str]]:
    out = kubectl(
        "exec", "-i", "pg-1", "-c", "postgres", "--",
        "psql", "-U", "postgres", "-d", db, "-At", "-F", "\t", "-c", query,
    )  # fmt: skip
    return [line.split("\t") for line in out.splitlines() if line]


def proxy(service: str, path: str) -> str:
    return kubectl("get", "--raw", f"/api/v1/namespaces/sv-dev/services/http:{service}:80/proxy{path}")


def wait_for(what: str, check, seconds: float):
    """Polls check() until it returns something true; that value, or None at the deadline."""
    deadline = time.monotonic() + seconds
    while True:
        value = check()
        if value or time.monotonic() > deadline:
            return value
        time.sleep(1)


def mails_for(order_id: str) -> list[dict]:
    """Mailpit's messages that mention the order, read from inside the cluster (the BFF pod has
    httpx); the order id is the only thing put on the command line."""
    code = (
        "import httpx, sys; r = httpx.get('http://mailpit:8025/dev/api/v1/search', "
        "params={'query': '\\\"' + sys.argv[1] + '\\\"', 'limit': 10}, timeout=10); print(r.text)"
    )
    out = kubectl("exec", "-i", "deploy/bff", "--", "python", "-c", code, order_id)
    return json.loads(out).get("messages", [])


def item(seller: Site, title: str, n: int) -> str:
    listing_id = seller.create_listing(
        {
            "title": title,
            "brand": "Verify",
            "category": "accessories",
            "size": "OS",
            "condition": "good",
            "price": "5.00",
            "description": "Made by verify_sprint3.sh (T075).",
        }
    )
    seller.add_photo(listing_id, f"t075-{n}.png", photos.png(n, 48, 60))
    seller.publish(listing_id)
    return listing_id


def checkout(buyer: Site, listing_id: str) -> tuple[str, str]:
    r = buyer.client.post(
        f"{SITE}/checkout/{listing_id}",
        data={"csrf_token": buyer.csrf, "idempotency_key": str(uuid.uuid4())},
    )
    secret_m = re.search(r'data-client-secret="([^"]+)"', r.text)
    order_m = re.search(r'data-order-url="/orders/([0-9a-f-]+)"', r.text)
    if r.status_code != 200 or not (secret_m and order_m):
        fail(f"checkout did not reach the pay page ({r.status_code} {r.headers.get('location', '')})")
    return order_m.group(1), unescape(secret_m.group(1))


def confirm(key: str, client_secret: str, card: str) -> httpx.Response:
    payment_intent = client_secret.split("_secret_")[0]
    return httpx.post(
        f"{STRIPE}/payment_intents/{payment_intent}/confirm",
        data={"payment_method": card, "return_url": SITE},
        auth=(key, ""),
        timeout=60,
    )


def order_status(order_id: str) -> tuple[str, str]:
    rows = sql("orders", f"select status, coalesce(failure_reason, '') from orders where id = '{order_id}'")
    return (rows[0][0], rows[0][1]) if rows else ("", "")


def listing_status(listing_id: str) -> str:
    return json.loads(proxy("listings", f"/listings/{listing_id}")).get("status", "")


def main() -> int:
    ca = subprocess.run(["mkcert", "-CAROOT"], capture_output=True, text=True, check=True).stdout.strip()
    pinned = pinned_context(ca + "/rootCA.pem")
    run = time.strftime("%m%d-%H%M%S")
    stripe_key = secret("stripe", "secret-key")

    def browser() -> httpx.Client:
        return httpx.Client(transport=LabTransport("127.0.0.1", resolve=lambda h: h, verify=pinned), timeout=60)

    with browser() as sc, browser() as bc:
        seller = Site(SITE, sc, lambda _: None)
        seller.sign_in(secret("verify-seller", "username"), secret("verify-seller", "password"))
        buyer = Site(SITE, bc, lambda _: None)
        buyer.sign_in(secret("verify-buyer", "username"), secret("verify-buyer", "password"))
        ok("verify seller and verify buyer signed in through the BFF login form")

        # ---------------------------------------------------------- a paid purchase
        paid_item = item(seller, f"Sprint 3 check {run} paid", 1)
        order_id, client_secret = checkout(buyer, paid_item)
        started = time.monotonic()
        r = confirm(stripe_key, client_secret, "pm_card_visa")
        if r.status_code != 200:
            fail(f"Stripe refused pm_card_visa: {r.status_code}")
        status = wait_for("paid", lambda: order_status(order_id)[0] == "paid" and "paid", 60)
        if not status:
            fail(f"order {order_id} is {order_status(order_id)[0] or 'missing'} 60s after paying")
        ok(f"a purchase with pm_card_visa ends paid ({time.monotonic() - started:.1f}s after confirming)")

        amount = int(sql("orders", f"select amount_cents from orders where id = '{order_id}'")[0][0])
        ledger = sql(
            "payments",
            f"select party, amount_cents from ledger_entry where order_id = '{order_id}' and kind = 'sale'",
        )
        parts = {party: int(cents) for party, cents in ledger}
        if set(parts) != {"platform", "seller"} or sum(parts.values()) != amount:
            fail(f"the ledger does not balance: {parts} for {amount} cents")
        ok(f"the ledger balances: platform {parts['platform']} + seller {parts['seller']} = {amount} cents")

        mails = wait_for("emails", lambda: len(mails_for(order_id)) >= 2 and mails_for(order_id), 30)
        if not mails:
            fail(f"expected 2 emails for order {order_id}, found {len(mails_for(order_id))}")
        to = sorted(a["Address"] for m in mails for a in m.get("To", []))
        if to != sorted([secret("verify-buyer", "username"), secret("verify-seller", "username")]):
            fail(f"the emails went to {to}")
        ok("two emails in Mailpit: the buyer's confirmation and the seller's sale")

        if listing_status(paid_item) != "sold":
            fail(f"the paid item is {listing_status(paid_item)}, not sold")
        ok("the paid item is sold")

        # ---------------------------------------------------------- a declined card
        declined_item = item(seller, f"Sprint 3 check {run} declined", 2)
        order_id, client_secret = checkout(buyer, declined_item)
        r = confirm(stripe_key, client_secret, "pm_card_chargeDeclined")
        if r.status_code != 402:
            fail(f"Stripe answered {r.status_code} to pm_card_chargeDeclined, not 402")
        state = wait_for("failed", lambda: order_status(order_id)[0] == "failed" and order_status(order_id), 60)
        if not state:
            fail(f"order {order_id} is {order_status(order_id)[0]} 60s after the decline")
        ok(f"a declined card ends failed ({state[1] or 'no reason'})")
        back = wait_for("available", lambda: listing_status(declined_item) == "available", 30)
        if not back:
            fail(f"the declined item is {listing_status(declined_item)}, not back on sale")
        ok("the declined item is back on sale")
        time.sleep(3)
        if mails_for(order_id):
            fail("a declined order sent an email")
        ok("no email for the declined order")
        seller.client.post(
            f"{SITE}/sell/listings/{declined_item}/delete", data={"csrf_token": seller.csrf}
        )

    # -------------------------------------------------------------- a message that dead-letters
    before = dead_letters()
    # Published from inside the Orders pod with Orders' own RabbitMQ user (AMQP_URL is in its
    # environment), so no credentials leave the cluster and the permissions are the real ones.
    publish = (
        "import asyncio, os, aio_pika\n"
        "async def main():\n"
        "    c = await aio_pika.connect(os.environ['AMQP_URL'])\n"
        "    ch = await c.channel(publisher_confirms=True)\n"
        "    ex = await ch.get_exchange('orders', ensure=True)\n"
        "    await ex.publish(aio_pika.Message(b'not json: verify_sprint3.sh'), routing_key='order.paid')\n"
        "    await c.close()\n"
        "asyncio.run(main())\n"
    )
    kubectl("exec", "-i", "deploy/orders", "--", "python", "-c", publish)
    arrived = wait_for("dead letter", lambda: dead_letters() > before, 30)
    if not arrived:
        fail("a malformed order event did not reach notifications.orders.dead")
    ok("a malformed order event is rejected into notifications.orders.dead (FR-017)")
    return 0


def dead_letters() -> int:
    out = kubectl(
        "exec", "rabbitmq-server-0", "-c", "rabbitmq", "--",
        "rabbitmqctl", "-q", "list_queues", "name", "messages",
    )  # fmt: skip
    for line in out.splitlines():
        name, _, count = line.partition("\t")
        if name == "notifications.orders.dead":
            return int(count)
    return 0


if __name__ == "__main__":
    sys.exit(main())
