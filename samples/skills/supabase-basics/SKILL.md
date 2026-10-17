---
name: supabase-basics
description: Starting a project with Supabase. A sample skill that ships with Skill Health, with one instruction that is no longer true.
---

# Supabase basics

Start a local stack in your project folder:

    npx supabase init
    npx supabase start

Sign a user in with their email and password:

    const { user, error } = await supabase.auth.signIn({ email, password })
