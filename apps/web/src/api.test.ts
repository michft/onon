import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

describe("API request headers", () => {
  afterEach(() => vi.unstubAllGlobals());

  beforeEach(() => {
    vi.resetModules();
    vi.stubGlobal("window", { location: { origin: "http://onon.test" } });
  });

  it("does not label a bodyless request as JSON", async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response(JSON.stringify({ code: "123456", expiresAt: "2026-01-01T00:00:00Z", qrPayload: "onon://pair" }), {
      status: 201,
      headers: { "Content-Type": "application/json" }
    }));
    vi.stubGlobal("fetch", fetchMock);

    const { api } = await import("./api");
    await api.createPairingCode();

    const init = fetchMock.mock.calls[0]?.[1];
    expect(new Headers(init?.headers).has("Content-Type")).toBe(false);
  });
});
