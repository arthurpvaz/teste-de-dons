import { useState } from 'react'
import { useNavigate } from 'react-router-dom'

import { useAuth } from '../../contexts/AuthContext'

export function Login() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')

  const { login } = useAuth()

  const navigate = useNavigate()

  async function handleSubmit(event) {
    event.preventDefault()

    setError('')

    const { error } = await login(email, password)

    if (error) {
      setError('E-mail ou senha inválidos.')
      return
    }

    navigate('/dashboard')
  }

  return (
    <main>
      <h1>IPB - Conecta Dons</h1>

      <h2>Login pastoral</h2>

      <form onSubmit={handleSubmit}>

        <div>
          <label>E-mail</label>

          <input
            type="email"
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            required
          />
        </div>

        <div>
          <label>Senha</label>

          <input
            type="password"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            required
          />
        </div>

        {error && <p>{error}</p>}

        <button type="submit">
          Entrar
        </button>

      </form>
    </main>
  )
}