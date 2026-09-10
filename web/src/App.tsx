import { Navigate, Route, Routes } from 'react-router-dom'
import { AuthProvider, useAuth } from '@/data/auth'
import { EyeProvider } from '@/data/eye'
import { StoreProvider } from '@/data/store'
import { Shell } from '@/ui/Shell'
import { SignIn } from '@/pages/SignIn'
import { Today } from '@/pages/Today'
import { Week } from '@/pages/Week'
import { Month } from '@/pages/Month'
import { Todos } from '@/pages/Todos'
import { Groups } from '@/pages/Groups'
import { Terms } from '@/pages/Terms'

function Routed() {
  const { session, ready } = useAuth()

  if (!ready) {
    return (
      <div className="flex h-full items-center justify-center text-sm text-muted">
        <span className="skeleton h-3 w-24 rounded" />
      </div>
    )
  }

  if (!session) return <SignIn />

  return (
    <StoreProvider>
      <EyeProvider>
        <Shell>
          <Routes>
            <Route path="/" element={<Navigate to="/today" replace />} />
            <Route path="/today" element={<Today />} />
            <Route path="/week" element={<Week />} />
            <Route path="/month" element={<Month />} />
            <Route path="/todos" element={<Todos />} />
            <Route path="/groups" element={<Groups />} />
            <Route path="/terms" element={<Terms />} />
            <Route path="*" element={<Navigate to="/today" replace />} />
          </Routes>
        </Shell>
      </EyeProvider>
    </StoreProvider>
  )
}

export default function App() {
  return (
    <AuthProvider>
      <Routed />
    </AuthProvider>
  )
}
