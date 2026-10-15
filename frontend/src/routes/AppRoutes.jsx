import {
  BrowserRouter,
  Navigate,
  Route,
  Routes
} from 'react-router-dom'

import { Login } from '../pages/Login/Login'
import { Dashboard } from '../pages/Dashboard/Dashboard'
import { MasterAdmin } from '../pages/MasterAdmin/MasterAdmin'

import { ProtectedRoute } from '../components/auth/ProtectedRoute'

export function AppRoutes() {
  return (
    <BrowserRouter>
      <Routes>

        <Route
          path="/"
          element={
            <Navigate
              to="/dashboard"
              replace
            />
          }
        />

        <Route
          path="/login"
          element={<Login />}
        />

        <Route
          path="/dashboard"
          element={
            <ProtectedRoute>
              <Dashboard />
            </ProtectedRoute>
          }
        />

        <Route
          path="/admin"
          element={
            <ProtectedRoute>
              <MasterAdmin />
            </ProtectedRoute>
          }
        />

      </Routes>
    </BrowserRouter>
  )
}