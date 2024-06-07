// learn more: https://fly.io/docs/reference/configuration/#services-http_checks
import type { LoaderFunctionArgs } from "@remix-run/node";

import { prisma } from "~/db.server";
const prepareRequest = (url: URL) => new Request(url, { method: "HEAD" });

const sendRequest = async (init: Request) => (await fetch(init)).ok;

const checkDatabase = async () => {
  try {
    return Boolean(await prisma.user.count());
  } catch (error) {
    return error;
  }
};

const checkNetwork = (url: URL) =>
  new Promise(async (resolve, reject) =>
    (await sendRequest(prepareRequest(url))) ? resolve(true) : reject(false),
  );

const healthCheck = (url: URL) =>
  Promise.all([checkDatabase(), checkNetwork(url)]);
export const loader = async ({ request }: LoaderFunctionArgs) => {
  const host =
    request.headers.get("X-Forwarded-Host") ?? request.headers.get("host");

  try {
    const url = new URL("/", `http://${host}`);
    // if we can connect to the database and make a simple query
    // and make a HEAD request to ourselves, then we're good.
    await healthCheck(url);
    return new Response("OK");
  } catch (error: unknown) {
    console.log("healthcheck ❌", { error });
    return new Response("ERROR", { status: 500 });
  }
};
