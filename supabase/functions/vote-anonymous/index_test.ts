import { assertEquals, assertNotEquals } from "jsr:@std/assert";
import { extractClientIp, hashIp, isValidSessionId } from "./index.ts";

Deno.test("extractClientIp prefers cf-connecting-ip over x-forwarded-for", () => {
  const headers = new Headers({
    "cf-connecting-ip": "1.2.3.4",
    "x-forwarded-for": "5.6.7.8, 9.10.11.12",
  });
  assertEquals(extractClientIp(headers), "1.2.3.4");
});

Deno.test("extractClientIp falls back to the first x-forwarded-for hop", () => {
  const headers = new Headers({
    "x-forwarded-for": "5.6.7.8, 9.10.11.12",
  });
  assertEquals(extractClientIp(headers), "5.6.7.8");
});

Deno.test("extractClientIp returns null when no IP header is present", () => {
  assertEquals(extractClientIp(new Headers()), null);
});

Deno.test("hashIp is deterministic for the same input and salt", async () => {
  const a = await hashIp("1.2.3.4", "salt");
  const b = await hashIp("1.2.3.4", "salt");
  assertEquals(a, b);
  assertEquals(a.length, 64); // hex-encoded SHA-256
});

Deno.test("hashIp differs for different IPs or salts", async () => {
  const a = await hashIp("1.2.3.4", "salt");
  const b = await hashIp("1.2.3.5", "salt");
  const c = await hashIp("1.2.3.4", "other-salt");
  assertNotEquals(a, b);
  assertNotEquals(a, c);
});

Deno.test("isValidSessionId accepts a well-formed UUID", () => {
  assertEquals(
    isValidSessionId("8c2f6b1a-3e4d-4a5b-9c1d-2f3e4a5b6c7d"),
    true,
  );
});

Deno.test("isValidSessionId rejects non-UUID or attacker-supplied values", () => {
  assertEquals(isValidSessionId("not-a-uuid"), false);
  assertEquals(isValidSessionId(""), false);
  assertEquals(isValidSessionId(null), false);
  assertEquals(isValidSessionId(undefined), false);
  assertEquals(isValidSessionId(12345), false);
  assertEquals(isValidSessionId("' OR 1=1 --"), false);
});
