import { useState } from 'react'
import { ArrowLeftIcon } from '@phosphor-icons/react'
import { useAuth } from '@/data/auth'
import { Button, ErrorNote, Field, TextInput } from '@/ui/primitives'

export function SignIn() {
  const { requestCode, verifyCode } = useAuth()
  const [step, setStep] = useState<'email' | 'code'>('email')
  const [email, setEmail] = useState('')
  const [code, setCode] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [note, setNote] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  async function sendCode() {
    if (!email.includes('@') || busy) return
    setBusy(true)
    setError(null)
    const { error: failure } = await requestCode(email.trim())
    setBusy(false)
    // The code may still exist even when the mail could not be sent, so always offer the box.
    setStep('code')
    if (failure) {
      setNote(`We could not send the mail: ${failure}`)
    } else {
      setNote(null)
    }
  }

  async function submitCode() {
    if (code.trim().length < 6 || busy) return
    setBusy(true)
    setError(null)
    const { error: failure } = await verifyCode(email.trim(), code.trim())
    setBusy(false)
    if (failure) setError(failure)
  }

  return (
    <div className="flex h-full items-center justify-center px-4">
      <div className="w-full max-w-[340px]">
        <p className="text-xl font-semibold tracking-tight">TimeControl</p>
        <p className="mt-1 text-sm text-muted">
          Your term, your week, and everything your groups put on it.
        </p>

        <div className="mt-6 flex flex-col gap-3">
          {error ? <ErrorNote>{error}</ErrorNote> : null}

          {step === 'email' ? (
            <>
              <Field label="Email">
                <TextInput
                  type="email"
                  inputMode="email"
                  autoComplete="email"
                  autoFocus
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') void sendCode()
                  }}
                  placeholder="you@university.edu"
                />
              </Field>
              <Button
                tone="primary"
                onClick={sendCode}
                disabled={!email.includes('@') || busy}
                className="w-full"
              >
                {busy ? 'Sending' : 'Send me a code'}
              </Button>
              <p className="text-tiny text-faint">
                No password. We mail a six digit code and a sign-in link; both last ten minutes.
              </p>
            </>
          ) : (
            <>
              <Field
                label="Six digit code"
                hint={`Sent to ${email}`}
                error={null}
              >
                <TextInput
                  inputMode="numeric"
                  autoComplete="one-time-code"
                  maxLength={6}
                  autoFocus
                  value={code}
                  onChange={(e) => setCode(e.target.value.replace(/\D/g, ''))}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') void submitCode()
                  }}
                  placeholder="000000"
                  className="num tracking-[0.4em]"
                />
              </Field>
              {note ? <p className="text-tiny text-muted">{note}</p> : null}
              <Button
                tone="primary"
                onClick={submitCode}
                disabled={code.length < 6 || busy}
                className="w-full"
              >
                {busy ? 'Checking' : 'Sign in'}
              </Button>
              <button
                type="button"
                onClick={() => {
                  setStep('email')
                  setCode('')
                  setError(null)
                  setNote(null)
                }}
                className="inline-flex items-center gap-1.5 self-start text-tiny text-muted hover:text-ink"
              >
                <ArrowLeftIcon size={12} />
                Use a different address
              </button>
            </>
          )}
        </div>
      </div>
    </div>
  )
}
