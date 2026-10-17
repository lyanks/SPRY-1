import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { UserMenu } from "@/components/user-menu";
import { buildLogoutUrl, buildOidcSettings } from "@/lib/auth-config";

const useAuth = vi.fn();
let enabled = true;

vi.mock("react-oidc-context", () => ({ useAuth: () => useAuth() }));
vi.mock("@/lib/auth-config", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/lib/auth-config")>()),
  get authEnabled() {
    return enabled;
  },
}));

describe("auth config", () => {
  it("returns to the site's own callback and asks for the code flow", () => {
    const settings = buildOidcSettings("https://d111.cloudfront.net");
    expect(settings.redirect_uri).toBe(
      "https://d111.cloudfront.net/auth/callback",
    );
    expect(settings.post_logout_redirect_uri).toBe(
      "https://d111.cloudfront.net/",
    );
    expect(settings.response_type).toBe("code");
    expect(settings.scope).toBe("openid email profile");
  });

  it("signs out through Cognito's own /logout", () => {
    const url = new URL(
      buildLogoutUrl(
        "https://d111.cloudfront.net",
        "https://spry.auth.eu-north-1.amazoncognito.com",
        "abc123",
      ),
    );
    expect(url.origin).toBe("https://spry.auth.eu-north-1.amazoncognito.com");
    expect(url.pathname).toBe("/logout");
    expect(url.searchParams.get("client_id")).toBe("abc123");
    expect(url.searchParams.get("logout_uri")).toBe(
      "https://d111.cloudfront.net/",
    );
  });
});

describe("UserMenu", () => {
  beforeEach(() => {
    enabled = true;
    useAuth.mockReset();
  });

  it("offers Sign in when nobody is signed in", () => {
    useAuth.mockReturnValue({ isLoading: false, isAuthenticated: false });
    render(<UserMenu />);
    expect(screen.getByRole("link", { name: /sign in/i })).toHaveAttribute(
      "href",
      "/login",
    );
  });

  it("shows the signed-in email and a Sign out button", async () => {
    const removeUser = vi.fn().mockResolvedValue(undefined);
    useAuth.mockReturnValue({
      isLoading: false,
      isAuthenticated: true,
      user: { profile: { email: "ada@example.com", sub: "1" } },
      removeUser,
    });
    // jsdom cannot navigate; only the call matters.
    vi.stubGlobal("location", {
      ...window.location,
      assign: vi.fn(),
      origin: "http://localhost",
    });

    render(<UserMenu />);
    expect(screen.getByTestId("signed-in-email")).toHaveTextContent(
      "ada@example.com",
    );

    await userEvent.click(screen.getByRole("button", { name: /sign out/i }));
    expect(removeUser).toHaveBeenCalledOnce();
    vi.unstubAllGlobals();
  });

  it("renders nothing while the session is loading", () => {
    useAuth.mockReturnValue({ isLoading: true });
    render(<UserMenu />);
    expect(screen.queryByRole("link")).not.toBeInTheDocument();
    expect(screen.queryByRole("button")).not.toBeInTheDocument();
  });

  it("renders nothing when sign-in is not configured", () => {
    enabled = false;
    const { container } = render(<UserMenu />);
    expect(container).toBeEmptyDOMElement();
    expect(useAuth).not.toHaveBeenCalled();
  });
});
