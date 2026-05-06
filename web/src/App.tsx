import { createBrowserRouter, RouterProvider } from "react-router-dom";
import { HomePage } from "./pages/HomePage";
import { JobDetailPage } from "./pages/JobDetailPage";

const router = createBrowserRouter([
  { path: "/", element: <HomePage /> },
  { path: "/jobs/:id", element: <JobDetailPage /> },
  { path: "*", element: <NotFound /> }
]);

function NotFound() {
  return (
    <div className="p-6 text-center">
      <h1 className="text-xl mb-2">Not found</h1>
      <a href="/" className="text-accent hover:underline">Go home</a>
    </div>
  );
}

export function App() {
  return <RouterProvider router={router} />;
}
