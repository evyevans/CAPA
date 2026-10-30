import httpx


class Hermes:
    def __init__(self, settings, client=None):
        self.client = client or httpx.AsyncClient(base_url=settings.hermes_url.rstrip('/'),
                                                  timeout=httpx.Timeout(20, connect=5))
        self.headers = {'Authorization': f'Bearer {settings.hermes_key}'}

    async def request(self, method, path, **kwargs):
        headers = {**self.headers, **kwargs.pop('headers', {})}
        response = await self.client.request(method, path, headers=headers, **kwargs)
        response.raise_for_status()
        return response.json()

    async def capabilities(self):
        return await self.request('GET', '/v1/capabilities')

    async def create(self, task):
        capabilities = await self.capabilities()
        if not capabilities.get('endpoints', {}).get('runs'):
            raise ValueError('This Hermes does not advertise the runs API')
        return await self.request('POST', '/v1/runs', json=task['payload'],
                                  headers={'Idempotency-Key': task['id']})

    async def status(self, run_id):
        return await self.request('GET', f'/v1/runs/{run_id}')

    async def connections(self):
        capabilities = await self.capabilities()
        endpoints = capabilities.get('endpoints', {})
        if not endpoints.get('toolsets'):
            return {'discovery_available': False, 'toolsets': [], 'skills': [],
                    'message': 'This Hermes does not advertise tool discovery. Configure tools in Hermes.'}
        toolsets = await self.request('GET', '/v1/toolsets')
        if isinstance(toolsets, dict):
            toolsets = toolsets.get('data')
        if not isinstance(toolsets, list):
            raise ValueError('Unsupported discovery shape')
        skills = []
        skills_unavailable = False
        if endpoints.get('skills'):
            try:
                skills = await self.request('GET', '/v1/skills')
                if isinstance(skills, dict):
                    skills = skills.get('data')
                if not isinstance(skills, list):
                    raise ValueError('Unsupported skills shape')
            except (httpx.HTTPError, ValueError):
                skills = []
                skills_unavailable = True
        # Allowlist metadata; never forward arbitrary plugin config or credentials.
        allowed = ('name', 'label', 'description', 'enabled', 'configured', 'tools')
        return {'discovery_available': True,
                'toolsets': [{k: v for k, v in item.items() if k in allowed} for item in toolsets if isinstance(item, dict)],
                'skills': [{k: v for k, v in item.items() if k in ('name', 'description', 'category')}
                           for item in skills if isinstance(item, dict)],
                'message': ('Toolsets available; skills discovery is currently unavailable in Hermes.'
                            if skills_unavailable else 'Tools and skills configured in your Hermes installation.')}

    async def control(self, run_id, action, body):
        capabilities = await self.capabilities()
        supported = bool(capabilities.get('endpoints', {}).get(f'run_{action}'))
        # v0.22.5 projects canonical clarify controls but omits the clarify route
        # from its capabilities endpoint table. The caller has already verified
        # a live generation-bound clarify prompt before reaching this method.
        if action == 'clarify':
            supported = supported or bool(capabilities.get('features', {}).get('run_approval_response'))
        if not supported:
            raise ValueError(f'This Hermes does not advertise {action}')
        return await self.request('POST', f'/v1/runs/{run_id}/{action}', json=body)
