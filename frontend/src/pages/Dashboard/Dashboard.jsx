import { useAuth } from '../../contexts/AuthContext'

export function Dashboard() {
  const { user, logout } = useAuth()

  async function handleLogout() {
    await logout()
  }

  return (
    <main>
      <h1>Dashboard Pastoral</h1>

      <p>
        Logado como: {user?.email}
      </p>

      <button onClick={handleLogout}>
        Sair
      </button>
    </main>
  )
}