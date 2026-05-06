import { createBrowserRouter, RouterProvider, Link } from "react-router-dom";
import { HomePage } from "./pages/HomePage";
import { JobDetailPage } from "./pages/JobDetailPage";
import { AppShell } from "./components/AppShell";

function NotFound() {
  return (
    <AppShell>
      <div className="surface-card p-12 text-center max-w-md mx-auto mt-16">
        <div className="text-6xl font-mono font-bold text-zinc-700 mb-4">404</div>
        <h1 className="text-xl font-semibold mb-2">Page not found</h1>
        <p className="text-sm text-zinc-400 mb-6">The route you followed doesn't exist on this server.</p>
        <Link to="/" className="btn-primary inline-block">Go home</Link>
      </div>
    </AppShell>
  );
}

const router = createBrowserRouter([
  { path: "/", element: <HomePage /> },
  { path: "/jobs/:id", element: <JobDetailPage /> },
  { path: "*", element: <NotFound /> }
]);

export function App() {
  return <RouterProvider router={router} />;
}
